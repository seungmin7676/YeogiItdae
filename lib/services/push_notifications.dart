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

  /// main()에서 Firebase 초기화 직후 한 번 호출한다. 웹은 별도 설정
  /// (VAPID 키 등)이 필요하므로 지금은 모바일에서만 동작시킨다.
  static Future<void> init() async {
    if (_initialized || kIsWeb) return;
    _initialized = true;

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

    await FirebaseMessaging.instance.requestPermission();
    FirebaseMessaging.onBackgroundMessage(firebaseMessagingBackgroundHandler);

    // 포그라운드: 시스템이 알림을 자동 표시하지 않으므로 직접 로컬 알림으로 띄운다.
    FirebaseMessaging.onMessage.listen(_showForeground);
    // 백그라운드에서 알림을 탭해 앱을 연 경우.
    FirebaseMessaging.onMessageOpenedApp.listen((m) => _handleTap(m.data));
    // 종료 상태에서 알림 탭으로 앱이 실행된 경우 — 네비게이터가 준비된 뒤 이동.
    final initial = await FirebaseMessaging.instance.getInitialMessage();
    if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _handleTap(initial.data),
      );
    }

    // 로그인 상태가 잡히면 토큰을 등록하고, 토큰 갱신도 반영한다. 이 서비스는
    // 앱 수명 내내 살아 있으므로 구독을 따로 취소하지 않는다.
    FirebaseAuth.instance.authStateChanges().listen((user) {
      if (user != null) registerToken();
    });
    FirebaseMessaging.instance.onTokenRefresh.listen(_saveToken);
  }

  /// 현재 로그인 사용자의 기기 토큰을 fcmTokens/{uid}에 등록한다.
  static Future<void> registerToken() async {
    if (kIsWeb) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) await _saveToken(token);
    } catch (_) {
      // 토큰 발급 실패(권한 거부 등)는 앱 동작을 막지 않는다.
    }
  }

  static Future<void> _saveToken(String token) async {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    // 한 계정이 여러 기기를 쓸 수 있으므로 배열로 모은다.
    await FirebaseFirestore.instance.collection('fcmTokens').doc(uid).set({
      'tokens': FieldValue.arrayUnion([token]),
      'updatedAt': FieldValue.serverTimestamp(),
    }, SetOptions(merge: true));
  }

  /// 로그아웃/회원탈퇴 시 signOut **이전에** 호출해, 이 기기 토큰을 지운다
  /// (안 지우면 다음에 이 기기를 쓰는 다른 계정으로 알림이 갈 수 있다).
  static Future<void> unregisterToken() async {
    if (kIsWeb) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;
    try {
      final token = await FirebaseMessaging.instance.getToken();
      if (token != null) {
        await FirebaseFirestore.instance.collection('fcmTokens').doc(uid).set({
          'tokens': FieldValue.arrayRemove([token]),
        }, SetOptions(merge: true));
      }
      await FirebaseMessaging.instance.deleteToken();
    } catch (_) {}
  }

  static Future<void> _showForeground(RemoteMessage message) async {
    final notification = message.notification;
    if (notification == null) return;
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
    final nav = rootNavigatorKey.currentState;
    if (nav == null) return;
    final type = data['type'] as String?;
    final chatId = data['chatId'] as String?;
    final itemId = data['itemId'] as String?;

    if ((type == 'chat_message' || type == 'chat_started') &&
        chatId != null &&
        chatId.isNotEmpty) {
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      final chatDoc = await FirebaseFirestore.instance
          .collection('chats')
          .doc(chatId)
          .get();
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
            .get();
        otherNickname = profile.data()?['nickname'] as String? ?? '상대방';
      }
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
      final itemDoc = await itemsCollection.doc(itemId).get();
      final context = rootNavigatorKey.currentContext;
      if (!itemDoc.exists || context == null || !context.mounted) return;
      showItemDetailSheet(context, LostFoundItem.fromDoc(itemDoc));
    }
  }
}
