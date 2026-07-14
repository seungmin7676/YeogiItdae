import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/feed_message.dart';
import 'chat_screen.dart';

/// 앱바의 알림 벨 아이콘. 읽지 않은 알림 개수를 배지로 표시한다.
class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('recipientUid', isEqualTo: uid)
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data?.docs.length ?? 0;
        return IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none_rounded),
              if (unreadCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.w700,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NotificationsScreen(),
              ),
            );
          },
        );
      },
    );
  }
}

/// 화면: 알림 목록
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  Future<void> _openNotification(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    await doc.reference.update({'read': true});
    if (!context.mounted) return;
    final type = data['type'] as String? ?? 'chat_started';
    if (type != 'chat_started') return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          chatId: data['chatId'] as String? ?? '',
          itemTitle: data['itemTitle'] as String? ?? '',
          otherNickname: data['senderNickname'] as String? ?? '알 수 없음',
          otherUid: data['senderUid'] as String? ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('알림'),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('recipientUid', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const FeedMessage(
              icon: Icons.error_outline_rounded,
              text: '알림을 불러오지 못했습니다.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const FeedMessage(
              icon: Icons.notifications_none_rounded,
              text: '알림이 없어요.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final read = data['read'] as bool? ?? false;
              final senderNickname =
                  data['senderNickname'] as String? ?? '알 수 없음';
              final itemTitle = data['itemTitle'] as String? ?? '';
              final type = data['type'] as String? ?? 'chat_started';
              final isHiddenNotice = type == 'item_hidden';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                color: read
                    ? AppColors.surface
                    : AppColors.primary.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: read
                        ? AppColors.line
                        : AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: Icon(
                    isHiddenNotice
                        ? Icons.visibility_off_outlined
                        : Icons.chat_bubble_outline,
                    color: read
                        ? AppColors.inkMuted
                        : (isHiddenNotice
                              ? AppColors.danger
                              : AppColors.primary),
                  ),
                  title: Text(
                    isHiddenNotice
                        ? "'$itemTitle' 게시글이 신고 누적으로 숨김 처리됐어요"
                        : '$senderNickname님이 채팅을 걸었어요',
                    style: TextStyle(
                      fontWeight: read ? FontWeight.w500 : FontWeight.w700,
                    ),
                  ),
                  subtitle: isHiddenNotice
                      ? const Text(
                          '마이페이지 > 내 글에서 확인할 수 있어요',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : Text(
                          itemTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: () => _openNotification(context, doc),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
