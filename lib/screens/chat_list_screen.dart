import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';
import '../widgets/count_badge.dart';
import '../widgets/feed_message.dart';
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

  const ChatListScreen({
    super.key,
    this.docs,
    this.hasError = false,
    this.blockedUids = const {},
  });

  @override
  State<ChatListScreen> createState() => _ChatListScreenState();
}

class _ChatListScreenState extends State<ChatListScreen> {
  final _searchController = TextEditingController();
  String _searchQuery = '';
  Timer? _searchDebounce;

  /// 나가기는 Firestore 서버 응답(스트림 갱신)을 받아야 목록에서 실제로
  /// 빠지는데, Dismissible은 onDismissed가 끝난 다음 프레임에 위젯이
  /// 트리에서 사라져 있기를 기대한다. 그 사이 시간차 때문에 "A dismissed
  /// Dismissible widget is still part of the tree" 오류가 났었다. 서버
  /// 응답을 기다리지 않고 로컬에서 즉시 감춰서 이 타이밍 문제를 없앤다.
  ///
  /// 서버가 clearedAt을 반영한 게 확인되면(didUpdateWidget) 바로 이 목록에서
  /// 빼야 한다 — 계속 남겨두면 상대가 나중에 새 메시지를 보내도 정상적인
  /// clearedAt vs lastMessageAt 재등장 로직을 이 임시 오버라이드가 계속
  /// 가려버려서 채팅방이 다시 안 생기는 문제가 있었다.
  final Set<String> _locallyLeftChatIds = {};

  @override
  void didUpdateWidget(covariant ChatListScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.docs == null || _locallyLeftChatIds.isEmpty) return;
    final uid = FirebaseAuth.instance.currentUser?.uid;
    if (uid == null) return;

    final presentIds = widget.docs!.map((doc) => doc.id).toSet();
    final confirmed = <String>{
      // 상대방 탈퇴 등으로 채팅방 문서 자체가 통째로 사라진 경우, clearedAt을
      // 확인할 방법이 없으니(문서가 없음) 그냥 정리 대상으로 본다.
      ..._locallyLeftChatIds.difference(presentIds),
    };
    for (final doc in widget.docs!) {
      if (!_locallyLeftChatIds.contains(doc.id)) continue;
      final clearedAt = Map<String, dynamic>.from(
        doc.data()['clearedAt'] as Map? ?? {},
      );
      if (clearedAt[uid] != null) confirmed.add(doc.id);
    }
    if (confirmed.isNotEmpty) {
      // build 도중 setState를 호출할 수 없으니 다음 프레임으로 미룬다.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          setState(() => _locallyLeftChatIds.removeAll(confirmed));
        }
      });
    }
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

  Future<bool> _confirmLeave(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('채팅방 나가기'),
        content: const Text(
          '채팅방을 나가시겠습니까?\n나가면 이 채팅방은 목록에서 사라지고, 이전 메시지 기록도 더 이상 볼 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () {
              HapticFeedback.mediumImpact();
              Navigator.pop(context, true);
            },
            child: const Text('나가기', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    return confirmed == true;
  }

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
      if (mounted) setState(() => _locallyLeftChatIds.remove(chatId));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('나가기에 실패했습니다: $e')));
      }
    }
  }

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
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: TextField(
              controller: _searchController,
              onChanged: _onSearchChanged,
              decoration: InputDecoration(
                hintText: '상대방 닉네임이나 글 제목으로 검색',
                hintStyle: const TextStyle(color: Color(0xFFB4B7C4)),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.inkMuted,
                ),
                suffixIcon: _searchController.text.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.inkMuted,
                        ),
                        tooltip: '검색어 지우기',
                        onPressed: () {
                          _searchDebounce?.cancel();
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
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
                      if (_locallyLeftChatIds.contains(doc.id)) return false;
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
                    text: query.isEmpty ? '진행 중인 채팅이 없어요.' : '검색 결과가 없습니다.',
                  );
                }

                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () => FirebaseFirestore.instance
                      .collection('chats')
                      .where('participants', arrayContains: uid)
                      .get(const GetOptions(source: Source.server)),
                  child: ListView.builder(
                    padding: const EdgeInsets.fromLTRB(20, 4, 20, 20),
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

                      return Dismissible(
                        key: ValueKey(chatId),
                        direction: DismissDirection.endToStart,
                        confirmDismiss: (_) => _confirmLeave(context),
                        onDismissed: (_) {
                          setState(() => _locallyLeftChatIds.add(chatId));
                          if (uid != null) _leaveChat(context, chatId, uid);
                        },
                        background: Container(
                          margin: const EdgeInsets.only(bottom: 12),
                          padding: const EdgeInsets.symmetric(horizontal: 20),
                          alignment: Alignment.centerRight,
                          decoration: BoxDecoration(
                            color: AppColors.danger,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: const Icon(
                            Icons.logout_rounded,
                            color: Colors.white,
                          ),
                        ),
                        child: Card(
                          margin: const EdgeInsets.only(bottom: 12),
                          elevation: 0,
                          color: AppColors.surface,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                            side: BorderSide(
                              color: isUnread
                                  ? AppColors.primary
                                  : AppColors.line,
                            ),
                          ),
                          child: ListTile(
                            contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 8,
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
                                    );
                                  },
                                ),
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
                                color: isUnread
                                    ? AppColors.ink
                                    : AppColors.inkMuted,
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
