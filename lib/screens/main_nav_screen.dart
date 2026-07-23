import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import '../widgets/app_user_data.dart';
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

  // chats 쿼리에 limit이 없으면 대화방이 많은 사용자일수록 앱을 열 때마다
  // 전체 채팅방 문서를 매번 구독하게 된다. 페이지당 50개씩 불러오고,
  // 부족하면 채팅 목록 화면에서 "더 보기"로 다음 페이지를 불러온다.
  static const int _pageSize = 50;
  int _loadedPages = 1;
  bool _isLoadingMoreChats = false;

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
    // 내가 차단한 사용자 목록은 AppUserData가 앱 전역에서 한 번만 구독해
    // 내려준다(main.dart 참고). 채팅 목록(ChatListScreen)과 하단 배지가
    // 같은 chats 쿼리를 각자 구독하면 실시간 리스너가 중복되므로, 그건
    // 계속 여기서 한 번만 구독해 두 곳에 내려준다.
    final blockedUids = AppUserData.of(context).blockedUids;

    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: uid)
          .orderBy('lastMessageAt', descending: true)
          .limit(_pageSize * _loadedPages)
          .snapshots(),
      builder: (context, snapshot) {
        if (_isLoadingMoreChats) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) setState(() => _isLoadingMoreChats = false);
          });
        }
        final unreadCount = _totalUnreadCount(
          snapshot.data?.docs,
          uid,
          blockedUids,
        );
        final docs = snapshot.data?.docs;
        final hasMoreChats =
            docs != null && docs.length == _pageSize * _loadedPages;
        final tabs = [
          const HomeFeedScreen(),
          const MyPostsScreen(),
          ChatListScreen(
            docs: docs,
            hasError: snapshot.hasError,
            blockedUids: blockedUids,
            hasMore: hasMoreChats,
            isLoadingMore: _isLoadingMoreChats,
            onLoadMore: () => setState(() {
              _isLoadingMoreChats = true;
              _loadedPages += 1;
            }),
          ),
          const ProfileScreen(),
        ];
        // v3 내비게이션 — 인디케이터 없는 플랫 바. 선택 상태는 잉크 채움
        // 아이콘 + 굵은 라벨로만 표현한다(색상 외 단서 제공).
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
                    size: 24,
                    color: AppColors.inkFaint,
                  ),
                  selectedIcon: Icon(
                    Icons.home_rounded,
                    size: 24,
                    color: AppColors.ink,
                  ),
                  label: '홈',
                ),
                const NavigationDestination(
                  icon: Icon(
                    Icons.receipt_long_outlined,
                    size: 24,
                    color: AppColors.inkFaint,
                  ),
                  selectedIcon: Icon(
                    Icons.receipt_long,
                    size: 24,
                    color: AppColors.ink,
                  ),
                  label: '내 글',
                ),
                NavigationDestination(
                  icon: IconWithCountBadge(
                    count: unreadCount,
                    icon: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      size: 24,
                      color: AppColors.inkFaint,
                    ),
                  ),
                  selectedIcon: IconWithCountBadge(
                    count: unreadCount,
                    icon: const Icon(
                      Icons.chat_bubble_rounded,
                      size: 24,
                      color: AppColors.ink,
                    ),
                  ),
                  label: '채팅',
                ),
                const NavigationDestination(
                  icon: Icon(
                    Icons.person_outline_rounded,
                    size: 24,
                    color: AppColors.inkFaint,
                  ),
                  selectedIcon: Icon(
                    Icons.person_rounded,
                    size: 24,
                    color: AppColors.ink,
                  ),
                  label: '마이페이지',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
