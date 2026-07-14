import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/count_badge.dart';
import 'chat_list_screen.dart';
import 'home_feed_screen.dart';
import 'my_posts_screen.dart';
import 'profile_screen.dart';

/// 로그인 후 하단 네비게이션바로 전환되는 메인 화면 (홈/내 글/채팅/마이페이지).
class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _currentIndex = 0;

  // 채팅 목록 화면(ChatListScreen)과 동일한 기준으로, 차단했거나 나간(그 뒤
  // 새 메시지가 없는) 채팅은 제외하고 나머지 채팅의 안읽은 메시지 수를 합산한다.
  int _totalUnreadCount(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs,
    String? uid,
    Set<String> blockedUids,
  ) {
    if (docs == null || uid == null) return 0;
    var total = 0;
    for (final doc in docs) {
      final data = doc.data();
      // 차단한 상대의 채팅은 새 메시지가 와도 하단 배지에 반영하지 않는다.
      final participants = List<String>.from(
        data['participants'] as List? ?? [],
      );
      final otherUid = participants.firstWhere(
        (u) => u != uid,
        orElse: () => '',
      );
      if (blockedUids.contains(otherUid)) continue;

      final clearedAt = Map<String, dynamic>.from(
        data['clearedAt'] as Map? ?? {},
      );
      final myClearedAt = clearedAt[uid] as Timestamp?;
      final lastMessageAt = data['lastMessageAt'] as Timestamp?;
      final isCleared =
          myClearedAt != null &&
          (lastMessageAt == null || lastMessageAt.compareTo(myClearedAt) <= 0);
      if (isCleared) continue;

      final unreadCountMap = Map<String, dynamic>.from(
        data['unreadCount'] as Map? ?? {},
      );
      total += (unreadCountMap[uid] as num?)?.toInt() ?? 0;
    }
    return total;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // 채팅 목록(ChatListScreen)과 하단 배지가 같은 chats 쿼리를 각자
    // 구독하면 실시간 리스너가 중복되므로, 여기서 한 번만 구독하고
    // 결과를 두 곳 모두에 내려준다. 내가 차단한 사용자 목록도 마찬가지로
    // 여기서 한 번만 구독해 두 곳에 내려준다.
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
              .collection('chats')
              .where('participants', arrayContains: uid)
              .snapshots(),
          builder: (context, snapshot) {
            final unreadCount = _totalUnreadCount(
              snapshot.data?.docs,
              uid,
              blockedUids,
            );
            final tabs = [
              const HomeFeedScreen(),
              const MyPostsScreen(),
              ChatListScreen(
                docs: snapshot.data?.docs,
                hasError: snapshot.hasError,
                blockedUids: blockedUids,
              ),
              const ProfileScreen(),
            ];
            return Scaffold(
              body: IndexedStack(index: _currentIndex, children: tabs),
              bottomNavigationBar: Container(
                decoration: const BoxDecoration(
                  color: AppColors.surface,
                  border: Border(top: BorderSide(color: AppColors.line)),
                ),
                child: NavigationBar(
                  selectedIndex: _currentIndex,
                  onDestinationSelected: (index) =>
                      setState(() => _currentIndex = index),
                  destinations: [
                    const NavigationDestination(
                      icon: Icon(
                        Icons.home_outlined,
                        color: AppColors.inkMuted,
                      ),
                      selectedIcon: Icon(
                        Icons.home_rounded,
                        color: AppColors.primary,
                      ),
                      label: '홈',
                    ),
                    const NavigationDestination(
                      icon: Icon(
                        Icons.receipt_long_outlined,
                        color: AppColors.inkMuted,
                      ),
                      selectedIcon: Icon(
                        Icons.receipt_long,
                        color: AppColors.primary,
                      ),
                      label: '내 글',
                    ),
                    NavigationDestination(
                      icon: IconWithCountBadge(
                        count: unreadCount,
                        icon: const Icon(
                          Icons.chat_bubble_outline_rounded,
                          color: AppColors.inkMuted,
                        ),
                      ),
                      selectedIcon: IconWithCountBadge(
                        count: unreadCount,
                        icon: const Icon(
                          Icons.chat_bubble_rounded,
                          color: AppColors.primary,
                        ),
                      ),
                      label: '채팅',
                    ),
                    const NavigationDestination(
                      icon: Icon(
                        Icons.person_outline_rounded,
                        color: AppColors.inkMuted,
                      ),
                      selectedIcon: Icon(
                        Icons.person_rounded,
                        color: AppColors.primary,
                      ),
                      label: '마이페이지',
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }
}
