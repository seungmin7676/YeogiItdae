import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

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
    title: '채팅 알림',
    subtitle: '누군가 내 게시글로 채팅을 걸었을 때',
  ),
  _NotificationTypeOption(
    field: 'notifyKeywordMatch',
    title: '키워드 알림',
    subtitle: '저장한 키워드와 일치하는 새 글이 등록됐을 때',
  ),
  _NotificationTypeOption(
    field: 'notifyReportResult',
    title: '신고 처리 알림',
    subtitle: '내가 신고한 글이 숨김 처리됐을 때',
  ),
  _NotificationTypeOption(
    field: 'notifyItemHidden',
    title: '게시글 숨김 알림',
    subtitle: '내 게시글이 신고 누적으로 숨김 처리됐을 때',
  ),
];

/// 화면: 알림 종류별 켜고 끄기. 꺼진 종류는 알림 목록/배지에서 걸러진다
/// (알림 자체는 계속 만들어지지만 본인 화면에서만 숨겨지는 방식).
class NotificationSettingsScreen extends StatelessWidget {
  const NotificationSettingsScreen({super.key});

  Future<void> _setPreference(String uid, String field, bool value) async {
    await FirebaseFirestore.instance.collection('userSettings').doc(uid).set({
      field: value,
    }, SetOptions(merge: true));
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
                          : (value) => _setPreference(uid, option.field, value),
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
