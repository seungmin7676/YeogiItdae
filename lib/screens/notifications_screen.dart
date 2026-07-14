import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/count_badge.dart';
import '../widgets/feed_message.dart';
import 'chat_screen.dart';

/// 앱바의 알림 벨 아이콘. 읽지 않은 알림 개수를 배지로 표시한다.
class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('blocks')
          .doc(uid ?? '_')
          .snapshots(),
      builder: (context, blocksSnapshot) {
        final blockedUids = Set<String>.from(
          (blocksSnapshot.data?.data()?['blockedUsers'] as Map?)?.keys ??
              const [],
        );
        return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('notifications')
              .where('recipientUid', isEqualTo: uid)
              .where('read', isEqualTo: false)
              .snapshots(),
          builder: (context, snapshot) {
            final unreadCount =
                snapshot.data?.docs.where((doc) {
                  final senderUid = doc.data()['senderUid'] as String?;
                  return !blockedUids.contains(senderUid);
                }).length ??
                0;
            return IconButton(
              icon: IconWithCountBadge(
                count: unreadCount,
                icon: const Icon(Icons.notifications_none_rounded),
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

    final senderUid = data['senderUid'] as String? ?? '';
    final fallbackNickname = data['senderNickname'] as String? ?? '알 수 없음';
    final profileDoc = await FirebaseFirestore.instance
        .collection('userPublicProfiles')
        .doc(senderUid)
        .get();
    final otherNickname =
        profileDoc.data()?['nickname'] as String? ?? fallbackNickname;
    if (!context.mounted) return;

    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          chatId: data['chatId'] as String? ?? '',
          itemTitle: data['itemTitle'] as String? ?? '',
          otherNickname: otherNickname,
          otherUid: senderUid,
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('알림 삭제'),
        content: const Text('이 알림을 삭제하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    return confirmed == true;
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
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('blocks')
            .doc(uid ?? '_')
            .snapshots(),
        builder: (context, blocksSnapshot) {
          final blockedUids = Set<String>.from(
            (blocksSnapshot.data?.data()?['blockedUsers'] as Map?)?.keys ??
                const [],
          );
          return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
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

              // 내가 차단한 사용자가 보낸 알림은 차단 사실이 드러나지 않도록
              // 완전히 걸러낸다(메시지·채팅 목록과 동일한 원칙).
              final docs = snapshot.data!.docs.where((doc) {
                final senderUid = doc.data()['senderUid'] as String?;
                return !blockedUids.contains(senderUid);
              }).toList();
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
                  final senderUid = data['senderUid'] as String? ?? '';
                  final fallbackNickname =
                      data['senderNickname'] as String? ?? '알 수 없음';
                  final itemTitle = data['itemTitle'] as String? ?? '';
                  final type = data['type'] as String? ?? 'chat_started';
                  final isHiddenNotice = type == 'item_hidden';

                  return Dismissible(
                    key: ValueKey(doc.id),
                    direction: DismissDirection.endToStart,
                    confirmDismiss: (_) => _confirmDelete(context),
                    onDismissed: (_) => doc.reference.delete(),
                    background: Container(
                      margin: const EdgeInsets.only(bottom: 12),
                      padding: const EdgeInsets.symmetric(horizontal: 20),
                      alignment: Alignment.centerRight,
                      decoration: BoxDecoration(
                        color: AppColors.danger,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: const Icon(
                        Icons.delete_outline,
                        color: Colors.white,
                      ),
                    ),
                    child: Card(
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
                        title: isHiddenNotice
                            ? Text(
                                "'$itemTitle' 게시글이 신고 누적으로 숨김 처리됐어요",
                                style: TextStyle(
                                  fontWeight: read
                                      ? FontWeight.w500
                                      : FontWeight.w700,
                                ),
                              )
                            : StreamBuilder<
                                DocumentSnapshot<Map<String, dynamic>>
                              >(
                                stream: FirebaseFirestore.instance
                                    .collection('userPublicProfiles')
                                    .doc(senderUid)
                                    .snapshots(),
                                builder: (context, profileSnapshot) {
                                  final senderNickname =
                                      profileSnapshot.data?.data()?['nickname']
                                          as String? ??
                                      fallbackNickname;
                                  return Text(
                                    '$senderNickname님이 채팅을 걸었어요',
                                    style: TextStyle(
                                      fontWeight: read
                                          ? FontWeight.w500
                                          : FontWeight.w700,
                                    ),
                                  );
                                },
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
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppColors.inkMuted,
                          ),
                          tooltip: '알림 삭제',
                          onPressed: () async {
                            if (await _confirmDelete(context)) {
                              await doc.reference.delete();
                            }
                          },
                        ),
                        onTap: () => _openNotification(context, doc),
                      ),
                    ),
                  );
                },
              );
            },
          );
        },
      ),
    );
  }
}
