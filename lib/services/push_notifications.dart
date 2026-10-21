import 'dart:async';
import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../models/lost_found_item.dart';
import '../screens/chat_screen.dart';
import '../screens/item_detail_sheet.dart';

/// 알림 탭 → 화면 이동에 쓰는 전역 네비게이터 키. main.dart의 MaterialApp에
/// 연결한다. 앱이 종료 상태에서 알림으로 실행될 때도 이 키로 라우팅한다.
final GlobalKey<NavigatorState> rootNavigatorKey = GlobalKey<NavigatorState>();

/// 백그라운드/종료 상태에서 도착한 메시지 핸들러. 백엔드가 notification
/// 페이로드를 함께 보내므로 시스템이 알림을 자동 표시한다 — 여기서는 별도
/// 표시가 필요 없다(데이터 전용 확장 대비로만 등록해 둔다). 최상위 함수여야
/// 하고 vm:entry-point로 표시해야 릴리스 빌드에서 트리 셰이킹되지 않는다.
@pragma('vm:entry-point')
Future<void> firebaseMessagingBackgroundHandler(RemoteMessage message) async {}

/// FCM 푸시 알림 전체를 담당한다: 권한 요청, 토큰 등록/해제, 포그라운드
/// 로컬 알림 표시, 알림 탭 시 딥링크 이동.
class PushNotifications {
  PushNotifications._();

  static final FlutterLocalNotificationsPlugin _local =
      FlutterLocalNotificationsPlugin();

  /// FCM이 백그라운드에서 쓰는 채널 id와 동일하게 맞춘다
  /// (AndroidManifest의 default_notification_channel_id 참고).
  static const AndroidNotificationChannel _channel = AndroidNotificationChannel(
    'high_importance_channel',
    '중요 알림',
    description: '채팅·키워드·신고 처리 등 주요 알림',
    importance: Importance.high,
  );

  static bool _initialized = false;
  static Future<void>? _initializing;
  static Timer? _initializationRetry;
  static bool _registeringToken = false;
  static final deviceStatus = ValueNotifier<String>('알림 상태를 확인해주세요.');
  static String? _readyUid;
  static String? _savedToken;
  static String? _savedUid;
  static bool _routing = false;
  static final _pendingTaps = <Map<String, dynamic>>[];
  static const _webVapidKey = String.fromEnvironment('FCM_WEB_VAPID_KEY');

  /// 초기화 실패는 재시도하고, 웹 권한은 알림 설정의 사용자 동작으로 요청한다.
  static Future<void> init() async {
    if (_initialized) return;
    try {
      await (_initializing ??= _initialize().whenComplete(
        () => _initializing = null,
      ));
      _initializationRetry?.cancel();
    } catch (_) {
      _initializationRetry?.cancel();
      _initializationRetry = Timer(const Duration(seconds: 15), () {
        unawaited(init());
      });
    }
  }

  static Future<void> _initialize() async {
    if (!await FirebaseMessaging.instance.isSupported()) {
      deviceStatus.value = '이 환경에서는 기기 알림을 지원하지 않아요.';
      return;
    }

    if (!kIsWeb) {
      const androidInit = AndroidInitializationSettings('@mipmap/ic_launcher');
      const darwinInit = DarwinInitializationSettings();
      await _local.initialize(
        settings: const InitializationSettings(
          android: androidInit,
          iOS: darwinInit,
        ),
        onDidReceiveNotificationResponse: (response) {
          final payload = response.payload;
          if (payload != null && payload.isNotEmpty) {
            _handleTap(_decodePayload(payload));
          }
        },
      );
      await _local
          .resolvePlatformSpecificImplementation<
            AndroidFlutterLocalNotificationsPlugin
          >()
          ?.createNotificationChannel(_channel);
      final launch = await _local.getNotificationAppLaunchDetails();
      final payload = launch?.notificationResponse?.payload;
      if (launch?.didNotificationLaunchApp == true && payload != null) {
        _pendingTaps.add(_decodePayload(payload));
      }

      // 알림 권한은 여기서 묻지 않는다. 앱을 처음 켠 순간(로그인 화면도 보기
      // 전)에 시스템 팝업을 띄우면 "이 앱이 왜 알림이 필요한지" 알 수 없어
      // 거부율이 높고, 한 번 거부하면 설정에서 직접 켜야 한다. 실제로 알림을
      // 받을 수 있는 상태(이메일 인증까지 끝난 로그인)가 됐을 때 묻는다.
      FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);
    }

    // 포그라운드: 시스템이 알림을 자동 표시하지 않으므로 직접 로컬 알림으로 띄운다.
    FirebaseMessaging.onMessage.listen((message) {
      unawaited(_showForeground(message).catchError((_) {}));
    });
    // 백그라운드에서 알림을 탭해 앱을 연 경우.
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _handleTap(m.data));
    // 종료 상태에서 알림 탭으로 앱이 실행된 경우 — 네비게이터가 준비된 뒤 이동.
    RemoteMessage? initial;
    if (!kIsWeb) {
      try {
        initial = await FirebaseMessaging.instance.getInitialMessage().timeout(
          const Duration(seconds: 5),
        );
      } catch (_) {}
    }
    if (initial != null) {
      await _handleTap(initial.data);
    }

    // 이메일 인증까지 끝난 로그인 상태가 되면 그때 권한을 묻고 토큰을
    // 등록한다. 계정당 한 번만 하도록 uid를 기억해둔다(userChanges는 프로필
    // 갱신·토큰 재발급 때도 발생한다). 이 서비스는 앱 수명 내내 살아 있으므로
    // 구독을 따로 취소하지 않는다.
    FirebaseAuth.instance.userChanges().listen((user) async {
      if (user == null || !user.emailVerified) {
        if (user == null) _permissionCheckedForUid = null;
        return;
      }
      if (_permissionCheckedForUid == user.uid) return;
      if (kIsWeb) {
        // 브라우저 권한 요청은 사용자가 알림 설정의 버튼을 누를 때 실행한다.
        await registerToken();
      } else {
        await enableForCurrentUser();
      }
      _permissionCheckedForUid = user.uid;
    });
    FirebaseMessaging.instance.onTokenRefresh.listen((token) async {
      try {
        await _saveToken(token);
      } catch (_) {}
    });
    Timer.periodic(const Duration(minutes: 1), (_) {
      unawaited(registerToken());
      unawaited(_drainTaps());
    });
    final query = Uri.base.queryParameters;
    if (kIsWeb && query['pushType'] != null) {
      _pendingTaps.add({
        'type': query['pushType'],
        'chatId': query['pushChatId'],
        'itemId': query['pushItemId'],
      });
    }
    _initialized = true;
    unawaited(_drainTaps());
  }

  /// 이번 세션에서 이미 권한을 묻고 토큰을 등록한 계정.
  static String? _permissionCheckedForUid;

  /// 현재 로그인 사용자의 기기 토큰을 fcmTokens/{uid}에 등록한다.
  static Future<void> registerToken() async {
    if (_registeringToken) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null || !user.emailVerified) return;
    _registeringToken = true;
    try {
      final settings = await FirebaseMessaging.instance
          .getNotificationSettings();
      if (settings.authorizationStatus != AuthorizationStatus.authorized &&
          settings.authorizationStatus != AuthorizationStatus.provisional) {
        deviceStatus.value = '이 기기의 알림이 꺼져 있어요. 기기·브라우저 설정에서 허용해주세요.';
        return;
      }
      final token = await FirebaseMessaging.instance
          .getToken(
            vapidKey: kIsWeb && _webVapidKey.isNotEmpty ? _webVapidKey : null,
          )
          .timeout(const Duration(seconds: 15));
      if (token != null && FirebaseAuth.instance.currentUser?.uid == user.uid) {
        await _saveToken(token);
        deviceStatus.value = '이 기기에서 알림을 받을 준비가 됐어요.';
      }
    } catch (_) {
      deviceStatus.value = '알림 연결을 마치지 못했어요. 연결 확인 후 다시 눌러주세요.';
    } finally {
      _registeringToken = false;
    }
  }

  static Future<void> enableForCurrentUser() async {
    try {
      await FirebaseMessaging.instance.requestPermission();
      await registerToken();
    } catch (_) {
      deviceStatus.value = '알림 권한을 확인하지 못했어요. 기기·브라우저 설정을 확인해주세요.';
    }
  }

  static void markNavigationReady() {
    _readyUid = FirebaseAuth.instance.currentUser?.uid;
    unawaited(_drainTaps());
    unawaited(registerToken());
  }

  static Future<void> _saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    if (_savedToken == token && _savedUid == uid) return;
    // 한 계정이 여러 기기를 쓸 수 있으므로 배열로 모은다.
    await FirebaseFirestore.instance
        .collection('fcmTokens')
        .doc(uid)
        .set({
          'tokens': FieldValue.arrayUnion([token]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true))
        .timeout(const Duration(seconds: 10));
    _savedToken = token;
    _savedUid = uid;
  }

  /// 로그아웃/회원탈퇴 시 signOut **이전에** 호출해, 이 기기 토큰을 지운다
  /// (안 지우면 다음에 이 기기를 쓰는 다른 계정으로 알림이 갈 수 있다).
  static Future<void> unregisterToken() async {
    _readyUid = null;
    _pendingTaps.clear();
    _savedToken = null;
    _savedUid = null;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('fcmTokens').doc(uid).set({
          'tokens': FieldValue.arrayRemove([token]),
          'updatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
    if (kIsWeb) {
      final context = rootNavigatorKey.currentContext;
      if (context != null && context.mounted) {
        ScaffoldMessenger.maybeOf(context)?.showSnackBar(
          SnackBar(
            content: Text(
              '${notification.title ?? '새 알림'}: ${notification.body ?? ''}',
            ),
            action: SnackBarAction(
              label: '보기',
              onPressed: () => _handleTap(message.data),
            ),
          ),
        );
      }
      return;
    }
    await _local.show(
      id: notification.hashCode,
      title: notification.title,
      body: notification.body,
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channel.id,
          _channel.name,
          channelDescription: _channel.description,
          importance: Importance.high,
          priority: Priority.high,
          icon: '@mipmap/ic_launcher',
        ),
        iOS: const DarwinNotificationDetails(),
      ),
      payload: jsonEncode(message.data),
    );
  }

  static Map<String, dynamic> _decodePayload(String payload) {
    try {
      final decoded = jsonDecode(payload);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  /// 알림 데이터의 type/chatId/itemId를 보고 알맞은 화면으로 이동한다.
  static Future<void> _handleTap(Map<String, dynamic> data) async {
    final key = '${data['type']}:${data['chatId']}:${data['itemId']}';
    if (!_pendingTaps.any(
      (entry) =>
          '${entry['type']}:${entry['chatId']}:${entry['itemId']}' == key,
    )) {
      _pendingTaps.add(Map.of(data));
    }
    await _drainTaps();
  }

  static Future<void> _drainTaps() async {
    final user = FirebaseAuth.instance.currentUser;
    if (_routing ||
        user == null ||
        !user.emailVerified ||
        _readyUid != user.uid ||
        rootNavigatorKey.currentState == null) {
      return;
    }
    _routing = true;
    try {
      while (_pendingTaps.isNotEmpty &&
          FirebaseAuth.instance.currentUser?.uid == user.uid) {
        final data = _pendingTaps.first;
        try {
          await _openNotification(data);
          _pendingTaps.remove(data);
        } on FirebaseException catch (error) {
          if (error.code == 'permission-denied' || error.code == 'not-found') {
            _pendingTaps.remove(data);
          } else {
            break;
          }
        } catch (_) {
          break;
        }
      }
    } finally {
      _routing = false;
    }
  }

  static Future<void> _openNotification(Map<String, dynamic> data) async {
    final openingUid = FirebaseAuth.instance.currentUser?.uid;
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    final type = data['type'] is String ? data['type'] as String : null;
    final chatId = data['chatId'] is String ? data['chatId'] as String : null;
    final itemId = data['itemId'] is String ? data['itemId'] as String : null;
    if ((chatId?.contains('/') ?? false) || (itemId?.contains('/') ?? false)) {
      return;
    }

    if ((type == 'chat_message' || type == 'chat_started') &&
        chatId != null &&
        chatId.isNotEmpty) {
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      final chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .get()
          .timeout(const Duration(seconds: 10));
      if (!chatDoc.exists) return;
      final cdata = chatDoc.data()!;
      final participants = List<String>.from(
        cdata['participants'] as List? ?? const [],
      );
      final otherUid = participants.firstWhere(
        (p) => p != myUid,
        orElse: () => '',
      );
      final nicknames = Map<String, dynamic>.from(
        cdata['participantNicknames'] as Map? ?? const {},
      );
      var otherNickname = nicknames[otherUid] as String? ?? '';
      if (otherNickname.isEmpty && otherUid.isNotEmpty) {
        final profile = await FirebaseFirestore.instance
            .collection('userPublicProfiles')
            .doc(otherUid)
            .get()
            .timeout(const Duration(seconds: 10));
        otherNickname = profile.data()?['nickname'] as String? ?? '상대방';
      }
      if (FirebaseAuth.instance.currentUser?.uid != openingUid) return;
      nav.push(
        MaterialPageRoute(
          builder: (context) => ChatScreen(
            chatId: chatId,
            itemTitle: cdata['itemTitle'] as String? ?? '',
            otherNickname: otherNickname.isEmpty ? '상대방' : otherNickname,
            otherUid: otherUid,
          ),
        ),
      );
      return;
    }

    if (itemId != null && itemId.isNotEmpty) {
      final itemDoc = await itemsCollection
          .doc(itemId)
          .get()
          .timeout(const Duration(seconds: 10));
      if (FirebaseAuth.instance.currentUser?.uid != openingUid) return;
      final context = rootNavigatorKey.currentContext;
      if (!itemDoc.exists || context == null || !context.mounted) return;
      showItemDetailSheet(context, LostFoundItem.fromDoc(itemDoc));
    }
  }
}
