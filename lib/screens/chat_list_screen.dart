import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/count_badge.dart';
import '../widgets/feed_message.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';

/// 화면: 내 채팅 목록
class ChatListScreen extends StatelessWidget {
  /// null이면 아직 로딩 중, 빈 리스트면 채팅이 없는 상태.
  /// MainNavScreen이 안읽음 배지용으로 구독 중인 스트림을 그대로 넘겨받아
  /// 같은 chats 쿼리를 두 번 구독하지 않도록 한다.
  final List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs;
  final bool hasError;

  /// 내가 차단한 사용자 uid 목록. 차단한 상대와의 채팅은 이후 상대가
  /// 메시지를 보내도 다시 나타나지 않도록 목록에서 완전히 제외한다.
  final Set<String> blockedUids;

  const ChatListScreen({
    super.key,
    this.docs,
    this.hasError = false,
    this.blockedUids = const {},
  });

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('채팅'),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: Builder(
        builder: (context) {
          if (hasError) {
            return const FeedMessage(
              icon: Icons.error_outline_rounded,
              text: '채팅 목록을 불러오지 못했습니다.',
            );
          }
          if (docs == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final visibleDocs =
              docs!.where((doc) {
                final data = doc.data();
                // 차단한 상대와의 채팅은 상대가 이후에 메시지를 보내
                // lastMessageAt이 갱신되더라도 다시 나타나지 않도록,
                // 나간(clearedAt) 여부와 무관하게 항상 목록에서 제외한다.
                final participants = List<String>.from(
                  data['participants'] as List? ?? [],
                );
                final otherUid = participants.firstWhere(
                  (u) => u != uid,
                  orElse: () => '',
                );
                if (blockedUids.contains(otherUid)) return false;

                final clearedAt = Map<String, dynamic>.from(
                  data['clearedAt'] as Map? ?? {},
                );
                final myClearedAt = clearedAt[uid] as Timestamp?;
                if (myClearedAt == null) return true;
                final lastMessageAt = data['lastMessageAt'] as Timestamp?;
                return lastMessageAt != null &&
                    lastMessageAt.compareTo(myClearedAt) > 0;
              }).toList()..sort((a, b) {
                final aAt = a.data()['lastMessageAt'] as Timestamp?;
                final bAt = b.data()['lastMessageAt'] as Timestamp?;
                if (aAt == null || bAt == null) return 0;
                return bAt.compareTo(aAt);
              });

          if (visibleDocs.isEmpty) {
            return const FeedMessage(
              icon: Icons.chat_bubble_outline_rounded,
              text: '진행 중인 채팅이 없어요.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: visibleDocs.length,
            itemBuilder: (context, index) {
              final data = visibleDocs[index].data();
              final participants = List<String>.from(
                data['participants'] as List? ?? [],
              );
              final otherUid = participants.firstWhere(
                (u) => u != uid,
                orElse: () => '',
              );
              final nicknames = Map<String, dynamic>.from(
                data['participantNicknames'] as Map? ?? {},
              );
              final otherNickname = nicknames[otherUid] as String? ?? '알 수 없음';
              final lastMessage = data['lastMessage'] as String? ?? '';
              final itemTitle = data['itemTitle'] as String? ?? '';

              final unreadCountMap = Map<String, dynamic>.from(
                data['unreadCount'] as Map? ?? {},
              );
              final unreadCount = (unreadCountMap[uid] as num?)?.toInt() ?? 0;
              final isUnread = unreadCount > 0;

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isUnread ? AppColors.primary : AppColors.line,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  leading: UserAvatar(nickname: otherNickname),
                  title: Text(
                    otherNickname,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  subtitle: Text(
                    lastMessage.isNotEmpty ? lastMessage : itemTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isUnread
                          ? FontWeight.w700
                          : FontWeight.normal,
                      color: isUnread ? AppColors.ink : AppColors.inkMuted,
                    ),
                  ),
                  trailing: isUnread ? CountBadge(count: unreadCount) : null,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatScreen(
                        chatId: visibleDocs[index].id,
                        itemTitle: itemTitle,
                        otherNickname: otherNickname,
                        otherUid: otherUid,
                      ),
                    ),
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
