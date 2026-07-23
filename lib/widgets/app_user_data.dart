import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

/// 로그인한 사용자의 차단 목록(blocks/{uid})과 알림 설정(userSettings/{uid})을
/// 트리 아래로 내려준다. 이 두 문서는 홈 피드, 알림, 채팅, 게시글 상세 등
/// 5곳 넘게 화면마다 각자 StreamBuilder로 따로 구독하고 있었는데, 그만큼
/// Firestore 실시간 리스너가 중복돼서 [AppUserDataProvider]가 한 번만
/// 구독한 결과를 여기 담아 내려준다.
class AppUserData extends InheritedWidget {
  final Set<String> blockedUids;

  /// blocks/{uid}.blockedUsers 원본({차단한 uid: 당시 저장해둔 닉네임}).
  /// 차단 관리 화면처럼 닉네임까지 필요한 화면에서만 이걸 쓰고, 그 외에는
  /// [blockedUids]만으로 충분하다.
  final Map<String, dynamic> blockedUsersRaw;
  final Map<String, dynamic> settings;

  /// blocks/{uid} 문서의 첫 스냅샷(또는 에러)이 아직 도착하지 않았으면
  /// false다. 차단 관리 화면처럼 "차단한 사용자가 없어요"와 "아직 로딩
  /// 중"을 구분해야 하는 화면에서 로딩 스피너를 보여줄지 판단하는 데 쓴다.
  /// (settings는 필드가 없을 때의 기본값 자체가 "정상 상태"와 같아서 —
  /// 예: 켜짐이 기본값 — 로딩 여부를 따로 구분할 필요가 없다.)
  final bool isReady;

  const AppUserData({
    super.key,
    required this.blockedUids,
    required this.blockedUsersRaw,
    required this.settings,
    required this.isReady,
    required super.child,
  });

  static AppUserData of(BuildContext context) {
    final result = context.dependOnInheritedWidgetOfExactType<AppUserData>();
    assert(
      result != null,
      'AppUserData가 트리에 없습니다. main.dart의 '
      'MaterialApp.builder가 AppUserDataProvider로 감싸고 있는지 확인해주세요.',
    );
    return result!;
  }

  bool isNotificationTypeEnabled(String type, Map<String, String> typeToField) {
    final field = typeToField[type];
    if (field == null) return true;
    return settings[field] as bool? ?? true;
  }

  @override
  bool updateShouldNotify(AppUserData oldWidget) {
    return isReady != oldWidget.isReady ||
        !setEquals(blockedUids, oldWidget.blockedUids) ||
        !mapEquals(blockedUsersRaw, oldWidget.blockedUsersRaw) ||
        !mapEquals(settings, oldWidget.settings);
  }
}

/// [AppUserData]를 앱 전역에 딱 한 번만 구독해 공급한다. 로그인한
/// 사용자가 바뀌어도(로그아웃 후 다른 계정 로그인 등) 스스로 반응할 수
/// 있도록 부모의 리빌드에 기대지 않고 authStateChanges를 직접 구독한다.
/// main.dart에서 MaterialApp.builder로 감싸 모든 라우트(푸시된 화면
/// 포함)에서 보이게 한다.
class AppUserDataProvider extends StatelessWidget {
  final Widget child;

  const AppUserDataProvider({super.key, required this.child});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, authSnapshot) {
        final uid = authSnapshot.data?.uid;
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('blocks')
              .doc(uid ?? '_')
              .snapshots(),
          builder: (context, blocksSnapshot) {
            final blockedUsersRaw = Map<String, dynamic>.from(
              blocksSnapshot.data?.data()?['blockedUsers'] as Map? ?? {},
            );
            final blockedUids = blockedUsersRaw.keys.toSet();
            return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('userSettings')
                  .doc(uid ?? '_')
                  .snapshots(),
              builder: (context, settingsSnapshot) {
                final settings =
                    settingsSnapshot.data?.data() ?? const <String, dynamic>{};
                return AppUserData(
                  blockedUids: blockedUids,
                  blockedUsersRaw: blockedUsersRaw,
                  settings: settings,
                  isReady:
                      blocksSnapshot.connectionState != ConnectionState.waiting,
                  child: child,
                );
              },
            );
          },
        );
      },
    );
  }
}
