import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/error_messages.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/count_badge.dart';
import '../widgets/feed_message.dart';
import '../widgets/optimistic_hide_mixin.dart';
import '../widgets/user_avatar.dart';
import 'chat_screen.dart';

/// 화면: 내 채팅 목록
class ChatListScreen extends StatefulWidget {
  /// null이면 아직 로딩 중, 빈 리스트면 채팅이 없는 상태.
  /// MainNavScreen이 안읽음 배지용으로 구독 중인 스트림을 그대로 넘겨받아
  /// 같은 chats 쿼리를 두 번 구독하지 않도록 한다.
  final List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs;
  final bool hasError;

  /// 내가 차단한 사용자 uid 목록. 차단한 상대와의 채팅은 이후 상대가
  /// 메시지를 보내도 다시 나타나지 않도록 목록에서 완전히 제외한다.
  final Set<String> blockedUids;

  /// 서버에 아직 불러오지 않은 채팅방이 더 있을 수 있는지 여부(페이지네이션).
  final bool hasMore;
  final bool isLoadingMore;
  final VoidCallback? onLoadMore;

  const ChatListScreen({
    super.key,
    this.docs,
    this.hasError = false,
    this.blockedUids = const {},
    this.hasMore = false,
    this.isLoadingMore = false,
    this.onLoadMore,
  });

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen>
    with OptimisticHideMixin<ChatListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  @override
  void didUpdateWidget(covariant ChatListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.docs == null) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    // 나가기(clearedAt 반영)가 서버에서 실제로 확인된 채팅방만 로컬
    // 오버라이드에서 정리한다. 문서 자체가 통째로 사라진 경우(상대방 탈퇴
    // 등)는 clearedAt을 확인할 방법이 없으니 mixin이 알아서 정리 대상으로
    // 본다.
    reconcileLocallyHidden(
      widget.docs!,
      isConfirmedGone: (doc) {
        final clearedAt = Map<String, dynamic>.from(
          doc.data()['clearedAt'] as Map? ?? {},
        );
        return clearedAt[uid] != null;
      },
    );
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = value);
    });
  }

  Future<bool> _confirmLeave(BuildContext context) => showConfirmDialog(
    context,
    title: '채팅방 나가기',
    content: '채팅방을 나가시겠습니까?\n나가면 이 채팅방은 목록에서 사라지고, 이전 메시지 기록도 더 이상 볼 수 없습니다.',
    confirmLabel: '나가기',
    danger: true,
    haptic: true,
  );

  Future<void> _leaveChat(
    BuildContext context,
    String chatId,
    String myUid,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('chats').doc(chatId).update({
        'clearedAt.$myUid': FieldValue.serverTimestamp(),
        'unreadCount.$myUid': 0,
      });
    } catch (e) {
      // 실패하면 서버에는 반영되지 않았으니 로컬에서 감췄던 것도 되돌려
      // 목록에 다시 보이게 한다.
      unhideLocally(chatId);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('나가기에 실패했습니다: ${friendlyErrorMessage(e)}')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('채팅')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kPagePadding,
              12,
              kPagePadding,
              10,
            ),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: appSearchDecoration(
                '상대방 닉네임이나 글 제목으로 검색',
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.inkMuted,
                          size: 18,
                        ),
                        tooltip: '검색어 지우기',
                        onPressed: () {
                          _searchDebounce?.cancel();
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
              ),
            ),
          ),
          const Divider(),
          Expanded(
            child: Builder(
              builder: (context) {
                if (widget.hasError) {
                  return const FeedMessage(
                    icon: Icons.error_outline_rounded,
                    text: '채팅 목록을 불러오지 못했습니다.',
                  );
                }
                if (widget.docs == null) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }

                final query = _searchQuery.trim().toLowerCase();

                final visibleDocs =
                    widget.docs!.where((doc) {
                      if (isLocallyHidden(doc.id)) return false;
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
                      if (widget.blockedUids.contains(otherUid)) {
                        return false;
                      }

                      final clearedAt = Map<String, dynamic>.from(
                        data['clearedAt'] as Map? ?? {},
                      );
                      final myClearedAt = clearedAt[uid] as Timestamp?;
                      final lastMessageAt = data['lastMessageAt'] as Timestamp?;
                      if (myClearedAt != null &&
                          !(lastMessageAt != null &&
                              lastMessageAt.compareTo(myClearedAt) > 0)) {
                        return false;
                      }

                      if (query.isEmpty) return true;
                      final nicknames = Map<String, dynamic>.from(
                        data['participantNicknames'] as Map? ?? {},
                      );
                      final otherNickname =
                          (nicknames[otherUid] as String? ?? '').toLowerCase();
                      final itemTitle = (data['itemTitle'] as String? ?? '')
                          .toLowerCase();
                      return otherNickname.contains(query) ||
                          itemTitle.contains(query);
                    }).toList()..sort((a, b) {
                      final aAt = a.data()['lastMessageAt'] as Timestamp?;
                      final bAt = b.data()['lastMessageAt'] as Timestamp?;
                      if (aAt == null || bAt == null) return 0;
                      return bAt.compareTo(aAt);
                    });

                if (visibleDocs.isEmpty) {
                  return FeedMessage(
                    icon: query.isEmpty
                        ? Icons.chat_bubble_outline_rounded
                        : Icons.search_off_rounded,
                    title: query.isEmpty ? '진행 중인 채팅이 없어요' : '검색 결과가 없어요',
                    text: query.isEmpty
                        ? '게시글 상세에서 채팅하기를 누르면\n작성자와 대화를 시작할 수 있어요.'
                        : '다른 검색어로 다시 찾아보세요.',
                  );
                }

                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () => FirebaseFirestore.instance
                      .collection('chats')
                      .where('participants', arrayContains: uid)
                      .get(const GetOptions(source: Source.server)),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 20),
                    itemCount: visibleDocs.length + (widget.hasMore ? 1 : 0),
                    separatorBuilder: (context, index) =>
                        const Divider(indent: 80),
                    itemBuilder: (context, index) {
                      if (index == visibleDocs.length) {
                        return LoadMoreButton(
                          isLoading: widget.isLoadingMore,
                          onPressed: widget.onLoadMore,
                        );
                      }
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
                      final otherNickname =
                          nicknames[otherUid] as String? ?? '알 수 없음';
                      final lastMessage = data['lastMessage'] as String? ?? '';
                      final itemTitle = data['itemTitle'] as String? ?? '';

                      final unreadCountMap = Map<String, dynamic>.from(
                        data['unreadCount'] as Map? ?? {},
                      );
                      final unreadCount =
                          (unreadCountMap[uid] as num?)?.toInt() ?? 0;
                      final isUnread = unreadCount > 0;
                      final chatId = visibleDocs[index].id;

                      // v3 — 보더 카드 대신 풀블리드 행. 안읽음 상태는
                      // 옅은 틴트 배경 + 굵은 텍스트 + 숫자 배지로 표현한다.
                      return Dismissible(
                        key: ValueKey(chatId),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => _confirmLeave(context),
                        onDismissed: (_) {
                          hideLocally(chatId);
                          if (uid != null) _leaveChat(context, chatId, uid);
                        },
                        background: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: kPagePadding,
                          ),
                          alignment: Alignment.centerRight,
                          color: AppColors.danger,
                          child: const Icon(
                            Icons.logout_rounded,
                            color: Colors.white,
                          ),
                        ),
                        child: Material(
                          color: isUnread
                              ? AppColors.primaryMuted
                              : Colors.transparent,
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: kPagePadding,
                              vertical: 6,
                            ),
                            leading:
                                StreamBuilder<
                                  DocumentSnapshot<Map<String, dynamic>>
                                >(
                                  stream: FirebaseFirestore.instance
                                      .collection('userPublicProfiles')
                                      .doc(otherUid)
                                      .snapshots(),
                                  builder: (context, profileSnapshot) {
                                    return UserAvatar(
                                      nickname: otherNickname,
                                      photoUrl:
                                          profileSnapshot.data
                                                  ?.data()?['photoUrl']
                                              as String?,
                                      size: 48,
                                    );
                                  },
                                ),
                            title: Text(
                              otherNickname,
                              style: const TextStyle(
                                fontWeight: FontWeight.w700,
                                fontSize: 15,
                                letterSpacing: -0.2,
                                color: AppColors.ink,
                              ),
                            ),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 2),
                              child: Text(
                                lastMessage.isNotEmpty
                                    ? lastMessage
                                    : itemTitle,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: isUnread
                                      ? FontWeight.w600
                                      : FontWeight.normal,
                                  color: isUnread
                                      ? AppColors.ink
                                      : AppColors.inkMuted,
                                ),
                              ),
                            ),
                            trailing: isUnread
                                ? CountBadge(count: unreadCount)
                                : null,
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
                        ),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
