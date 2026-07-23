import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/error_messages.dart';
import '../theme/app_theme.dart';
import '../widgets/app_user_data.dart';
import '../widgets/feed_message.dart';

/// 화면: 차단한 사용자 관리
class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  Future<void> _unblock(
    BuildContext context,
    String uid,
    String otherUid,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('blocks').doc(uid).update({
        'blockedUsers.$otherUid': FieldValue.delete(),
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('차단 해제에 실패했습니다: ${friendlyErrorMessage(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('차단 관리')),
      body: Builder(
        builder: (context) {
          final appUserData = AppUserData.of(context);
          if (!appUserData.isReady) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          final blockedUsers = appUserData.blockedUsersRaw;

          if (blockedUsers.isEmpty) {
            return const FeedMessage(
              icon: Icons.block_outlined,
              title: '차단한 사용자가 없어요',
              text: '채팅방 메뉴에서 사용자를 차단하면\n여기에서 관리할 수 있어요.',
            );
          }

          final entries = blockedUsers.entries.toList();
          return ListView.separated(
            padding: const EdgeInsets.symmetric(vertical: 8),
            itemCount: entries.length,
            separatorBuilder: (context, index) =>
                const Divider(indent: kPagePadding),
            itemBuilder: (context, index) {
              final otherUid = entries[index].key;
              final fallbackNickname =
                  entries[index].value as String? ?? '알 수 없음';
              return ListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: kPagePadding,
                  vertical: 2,
                ),
                title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('userPublicProfiles')
                      .doc(otherUid)
                      .snapshots(),
                  builder: (context, profileSnapshot) {
                    final nickname =
                        profileSnapshot.data?.data()?['nickname'] as String? ??
                        fallbackNickname;
                    return Text(
                      nickname,
                      style: const TextStyle(
                        fontWeight: FontWeight.w600,
                        fontSize: 15,
                      ),
                    );
                  },
                ),
                trailing: OutlinedButton(
                  onPressed: uid == null
                      ? null
                      : () => _unblock(context, uid, otherUid),
                  style: OutlinedButton.styleFrom(
                    minimumSize: const Size(0, 36),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    textStyle: const TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  child: const Text('차단 해제'),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
