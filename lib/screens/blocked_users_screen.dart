import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('차단 해제에 실패했습니다: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('차단 관리'),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('blocks')
            .doc(uid ?? '_')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final blockedUsers = Map<String, dynamic>.from(
            snapshot.data?.data()?['blockedUsers'] as Map? ?? {},
          );

          if (blockedUsers.isEmpty) {
            return const FeedMessage(
              icon: Icons.block_outlined,
              text: '차단한 사용자가 없어요.',
            );
          }

          final entries = blockedUsers.entries.toList();
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final otherUid = entries[index].key;
              final fallbackNickname =
                  entries[index].value as String? ?? '알 수 없음';
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.line),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  title: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('userPublicProfiles')
                        .doc(otherUid)
                        .snapshots(),
                    builder: (context, profileSnapshot) {
                      final nickname =
                          profileSnapshot.data?.data()?['nickname']
                              as String? ??
                          fallbackNickname;
                      return Text(
                        nickname,
                        style: const TextStyle(fontWeight: FontWeight.w600),
                      );
                    },
                  ),
                  trailing: TextButton(
                    onPressed: uid == null
                        ? null
                        : () => _unblock(context, uid, otherUid),
                    child: const Text('차단 해제'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
