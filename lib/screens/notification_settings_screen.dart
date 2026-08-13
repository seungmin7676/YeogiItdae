import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/error_messages.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/app_user_data.dart';

class _NotificationTypeOption {
  final String field;
  final String title;
  final String subtitle;

  const _NotificationTypeOption({
    required this.field,
    required this.title,
    required this.subtitle,
  });
}

const List<_NotificationTypeOption> _kNotificationTypes = [
  _NotificationTypeOption(
    field: 'notifyChatStarted',
    title: '채팅 시작 알림',
    subtitle: '누군가 내 게시글로 채팅을 걸었을 때',
  ),
  _NotificationTypeOption(
    field: 'notifyChatMessage',
    title: '채팅 메시지 알림',
    subtitle: '진행 중인 채팅에 새 메시지가 왔을 때',
  ),
  _NotificationTypeOption(
    field: 'notifyKeywordMatch',
    title: '키워드 알림',
    subtitle: '저장한 키워드와 일치하는 새 글이 등록됐을 때',
  ),
  _NotificationTypeOption(
    field: 'notifyReportResult',
    title: '신고 처리 알림',
    subtitle: '내가 신고한 글이 처리됐을 때',
  ),
  _NotificationTypeOption(
    field: 'notifyItemHidden',
    title: '게시글 처리 알림',
    subtitle: '내 게시글이 관리자 검토로 숨김·삭제됐을 때',
  ),
];

/// 화면: 알림 종류별 켜고 끄기. 꺼진 종류는 알림 목록/배지에서 걸러진다
/// (알림 자체는 계속 만들어지지만 본인 화면에서만 숨겨지는 방식).
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  /// 스위치를 바꾸면 곧바로 Firestore에 쓴다. 실패(오프라인·권한)를 그냥
  /// 두면 처리되지 않은 비동기 예외가 되고, 화면의 스위치는 AppUserData가
  /// 내려주는 서버 값을 그대로 그리므로 조용히 원래 자리로 되돌아가 사용자는
  /// "왜 안 바뀌지?"만 겪게 된다. 실패 이유를 반드시 알려준다.
  Future<void> _setPreference(
    BuildContext context,
    String uid,
    String field,
    bool value,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection('userSettings').doc(uid).set({
        field: value,
      }, SetOptions(merge: true));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('알림 설정을 저장하지 못했어요: ${friendlyErrorMessage(e)}')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('알림 설정')),
      body: Builder(
        builder: (context) {
          // 알림 설정은 AppUserData가 앱 전역에서 이미 한 번 구독해 내려주고
          // 있으므로(main.dart 참고), 이 화면에서 또 구독하지 않고 그대로 쓴다.
          // 스위치를 바꾸면 Firestore에 쓰는 즉시 AppUserData의 구독이 최신
          // 값을 반영해 다시 내려준다.
          final settings = AppUserData.of(context).settings;
          return ListView(
            padding: const EdgeInsets.all(kPagePadding),
            children: [
              GroupSurface(
                children: [
                  for (final option in _kNotificationTypes)
                    SwitchListTile(
                      activeThumbColor: AppColors.primary,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      title: Text(
                        option.title,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          fontSize: 14.5,
                        ),
                      ),
                      subtitle: Text(
                        option.subtitle,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      value: settings[option.field] as bool? ?? true,
                      onChanged: uid == null
                          ? null
                          : (value) => _setPreference(
                              context,
                              uid,
                              option.field,
                              value,
                            ),
                    ),
                ],
              ),
            ],
          );
        },
      ),
    );
  }
}
