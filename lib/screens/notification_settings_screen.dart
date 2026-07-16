import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

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
      appBar: AppBar(
        title: const Text('알림 설정'),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('userSettings')
            .doc(uid ?? '_')
            .snapshots(),
        builder: (context, snapshot) {
          final settings = snapshot.data?.data() ?? const {};
          return ListView.separated(
            padding: const EdgeInsets.all(20),
            itemCount: _kNotificationTypes.length,
            separatorBuilder: (context, index) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final option = _kNotificationTypes[index];
              final enabled = settings[option.field] as bool? ?? true;
              return Container(
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(color: AppColors.line),
                ),
                child: SwitchListTile(
                  activeThumbColor: AppColors.primary,
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  title: Text(
                    option.title,
                    style: const TextStyle(fontWeight: FontWeight.w700),
                  ),
                  subtitle: Text(
                    option.subtitle,
                    style: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.inkMuted,
                    ),
                  ),
                  value: enabled,
                  onChanged: uid == null
                      ? null
                      : (value) => _setPreference(uid, option.field, value),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
