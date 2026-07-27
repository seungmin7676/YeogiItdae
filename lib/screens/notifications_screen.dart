import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/lost_found_item.dart';
import '../services/error_messages.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/app_user_data.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/count_badge.dart';
import '../widgets/feed_message.dart';
import '../widgets/optimistic_hide_mixin.dart';
import 'chat_screen.dart';
import 'item_detail_sheet.dart';

/// 알림 종류(type)에 대응하는 userSettings 필드. 필드가 없으면 기본값은 켜짐이다.
const Map<String, String> _kNotificationTypeToSettingField = {
  'chat_started': 'notifyChatStarted',
  'keyword_match': 'notifyKeywordMatch',
  'report_result': 'notifyReportResult',
  'item_hidden': 'notifyItemHidden',
  'item_removed': 'notifyItemHidden',
};

bool _isNotificationTypeEnabled(Map<String, dynamic> settings, String type) {
  final field = _kNotificationTypeToSettingField[type];
  if (field == null) return true;
  return settings[field] as bool? ?? true;
}

/// 앱바의 알림 벨 아이콘. 읽지 않은 알림 개수를 배지로 표시한다.
class NotificationBellButton extends StatelessWidget {
  const NotificationBellButton({super.key});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    final appUserData = AppUserData.of(context);
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('recipientUid', isEqualTo: uid)
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final unreadCount =
            snapshot.data?.docs.where((doc) {
              final data = doc.data();
              final senderUid = data['senderUid'] as String?;
              final type = data['type'] as String? ?? 'chat_started';
              return !appUserData.blockedUids.contains(senderUid) &&
                  _isNotificationTypeEnabled(appUserData.settings, type);
            }).length ??
            0;
        return IconButton(
          icon: IconWithCountBadge(
            count: unreadCount,
            icon: const Icon(Icons.notifications_none_rounded),
          ),
          tooltip: '알림',
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
class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen>
    with OptimisticHideMixin<NotificationsScreen> {
  // 알림도 items/chats와 마찬가지로 limit 없이 전체를 구독하면 오래
  // 쓴 계정일수록 앱을 열 때마다 알림 전체 이력을 읽어오게 된다.
  static const int _pageSize = 30;
  int _loadedPages = 1;
  bool _isLoadingMore = false;

  Future<void> _deleteNotification(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    hideLocally(doc.id);
    try {
      await doc.reference.delete();
    } catch (e) {
      unhideLocally(doc.id);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('알림 삭제에 실패했습니다: ${friendlyErrorMessage(e)}')),
        );
      }
    }
  }

  Future<void> _openNotification(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    try {
      await doc.reference.update({'read': true});
    } catch (_) {
      // 읽음 표시 실패(예: 다른 기기에서 방금 삭제됨)는 알림 열기 자체를
      // 막을 정도로 치명적이지 않으므로 조용히 넘어간다.
    }
    if (!context.mounted) return;
    // type이 없거나 알 수 없는 값이면 채팅으로 오인해 열지 않도록,
    // 결측 시 'chat_started'로 임의 대체하지 않고 명시적으로 처리한다.
    final type = data['type'] as String?;

    // 게시글 숨김 알림도 keyword_match와 동일하게 상세 시트를 열어준다.
    // 숨김 처리된 글이라도 작성자 본인은 상세 시트에서 이의제기를 남길 수
    // 있어야 하므로, 알림에서 곧장 그 화면으로 보내는 게 자연스럽다.
    if (type == 'keyword_match' || type == 'item_hidden') {
      final itemId = data['itemId'] as String?;
      if (itemId == null) return;
      final itemDoc = await itemsCollection.doc(itemId).get();
      if (!context.mounted || !itemDoc.exists) return;
      showItemDetailSheet(context, LostFoundItem.fromDoc(itemDoc));
      return;
    }
    if (type != 'chat_started') return;

    // chatId가 없는 채팅 알림(손상되거나 옛 형식의 데이터)은 빈 채팅방으로
    // 이동해버리지 않도록 아예 열지 않는다.
    final chatId = data['chatId'] as String? ?? '';
    if (chatId.isEmpty) return;

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
          chatId: chatId,
          itemTitle: data['itemTitle'] as String? ?? '',
          otherNickname: otherNickname,
          otherUid: senderUid,
        ),
      ),
    );
  }

  Future<bool> _confirmDelete(BuildContext context) => showConfirmDialog(
    context,
    title: '알림 삭제',
    content: '이 알림을 삭제하시겠습니까?',
    confirmLabel: '삭제',
    danger: true,
  );

  bool _isMarkingAllRead = false;

  Future<void> _markAllRead(BuildContext context, String? uid) async {
    // 연속 탭으로 같은 조회+배치 커밋이 중복 실행되지 않도록 막는다.
    if (uid == null || _isMarkingAllRead) return;
    _isMarkingAllRead = true;
    final messenger = ScaffoldMessenger.of(context);
    try {
      final unread = await FirebaseFirestore.instance
          .collection('notifications')
          .where('recipientUid', isEqualTo: uid)
          .where('read', isEqualTo: false)
          .get();
      if (unread.docs.isEmpty) {
        messenger.showSnackBar(const SnackBar(content: Text('읽지 않은 알림이 없어요.')));
        return;
      }
      // Firestore 배치는 최대 500개 작업까지만 허용하므로 청크로 나눠 커밋한다
      // (오래 알림을 안 읽은 계정은 읽지 않은 알림이 500개를 넘을 수 있다).
      const chunkSize = 450;
      for (var i = 0; i < unread.docs.length; i += chunkSize) {
        final chunk = unread.docs.sublist(
          i,
          (i + chunkSize) > unread.docs.length
              ? unread.docs.length
              : i + chunkSize,
        );
        final batch = FirebaseFirestore.instance.batch();
        for (final doc in chunk) {
          batch.update(doc.reference, {'read': true});
        }
        await batch.commit();
      }
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('읽음 처리에 실패했습니다: ${friendlyErrorMessage(e)}')),
      );
    } finally {
      _isMarkingAllRead = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('알림'),
        actions: [
          TextButton(
            onPressed: () => _markAllRead(context, uid),
            child: const Text('모두 읽음'),
          ),
        ],
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('recipientUid', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(_pageSize * _loadedPages)
            .snapshots(),
        builder: (context, snapshot) {
          final appUserData = AppUserData.of(context);
          final blockedUids = appUserData.blockedUids;
          final settings = appUserData.settings;
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
          if (_isLoadingMore) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (mounted) setState(() => _isLoadingMore = false);
            });
          }
          final canLoadMore =
              snapshot.data!.docs.length == _pageSize * _loadedPages;

          // 내가 차단한 사용자가 보낸 알림은 차단 사실이 드러나지 않도록
          // 완전히 걸러내고, 알림 설정에서 꺼둔 종류와 방금 로컬에서
          // 삭제한(아직 서버 확인 전인) 항목도 함께 제외한다
          // (메시지·채팅 목록과 동일한 원칙 — 알림 자체는 계속 만들어지지만
          // 본인 화면에서만 걸러진다).
          final docs = snapshot.data!.docs.where((doc) {
            if (isLocallyHidden(doc.id)) return false;
            final data = doc.data();
            final senderUid = data['senderUid'] as String?;
            final type = data['type'] as String? ?? 'chat_started';
            return !blockedUids.contains(senderUid) &&
                _isNotificationTypeEnabled(settings, type);
          }).toList();

          // 서버가 삭제를 확정한 뒤에도(문서가 스냅샷에서 완전히
          // 사라진 뒤에도) 로컬 오버라이드에 계속 남아있지 않도록 정리한다.
          reconcileLocallyHidden(snapshot.data!.docs);

          if (docs.isEmpty) {
            return const FeedMessage(
              icon: Icons.notifications_none_rounded,
              title: '알림이 없어요',
              text: '새 채팅, 키워드 일치, 신고 처리 소식이\n여기에 표시돼요.',
            );
          }

          return RefreshIndicator(
            color: AppColors.primary,
            onRefresh: () => FirebaseFirestore.instance
                .collection('notifications')
                .where('recipientUid', isEqualTo: uid)
                .orderBy('createdAt', descending: true)
                .get(const GetOptions(source: Source.server)),
            child: ListView.separated(
              padding: const EdgeInsets.only(bottom: 24),
              itemCount: docs.length + (canLoadMore ? 1 : 0),
              separatorBuilder: (context, index) => const Divider(indent: 72),
              itemBuilder: (context, index) {
                if (index == docs.length) {
                  return LoadMoreButton(
                    isLoading: _isLoadingMore,
                    onPressed: () => setState(() {
                      _isLoadingMore = true;
                      _loadedPages += 1;
                    }),
                  );
                }
                final doc = docs[index];
                final data = doc.data();
                final read = data['read'] as bool? ?? false;
                final senderUid = data['senderUid'] as String? ?? '';
                final fallbackNickname =
                    data['senderNickname'] as String? ?? '알 수 없음';
                final itemTitle = data['itemTitle'] as String? ?? '';
                final keyword = data['keyword'] as String? ?? '';
                final matchType = data['matchType'] as String? ?? 'keyword';
                final type = data['type'] as String? ?? 'chat_started';
                final isHiddenNotice = type == 'item_hidden';
                final isRemovedNotice = type == 'item_removed';
                final isReportResult = type == 'report_result';
                final isKeywordMatch = type == 'keyword_match';

                // v3 — 보더 카드 대신 풀블리드 행. 안읽음은 옅은 틴트 배경 +
                // 굵은 텍스트, 아이콘은 종류별 색의 원형 틴트 안에 둔다.
                final iconColor = isHiddenNotice || isRemovedNotice
                    ? AppColors.danger
                    : isReportResult
                    ? AppColors.found
                    : AppColors.primary;
                return Dismissible(
                  key: ValueKey(doc.id),
                  direction: DismissDirection.endToStart,
                  confirmDismiss: (_) => _confirmDelete(context),
                  onDismissed: (_) => _deleteNotification(context, doc),
                  background: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: kPagePadding,
                    ),
                    alignment: Alignment.centerRight,
                    color: AppColors.danger,
                    child: const Icon(
                      Icons.delete_outline,
                      color: Colors.white,
                    ),
                  ),
                  child: Material(
                    color: read ? Colors.transparent : AppColors.primaryMuted,
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: kPagePadding,
                        vertical: 4,
                      ),
                      leading: Container(
                        width: 40,
                        height: 40,
                        decoration: BoxDecoration(
                          color: read
                              ? AppColors.surfaceAlt
                              : iconColor.withValues(alpha: 0.12),
                          shape: BoxShape.circle,
                        ),
                        alignment: Alignment.center,
                        child: Icon(
                          isRemovedNotice
                              ? Icons.delete_outline_rounded
                              : isHiddenNotice
                              ? Icons.visibility_off_outlined
                              : isReportResult
                              ? Icons.flag_outlined
                              : isKeywordMatch
                              ? Icons.notifications_active_outlined
                              : Icons.chat_bubble_outline,
                          size: 18,
                          color: read ? AppColors.inkMuted : iconColor,
                        ),
                      ),
                      title: isRemovedNotice
                          ? Text(
                              "'$itemTitle' 게시글이 신고 검토 후 삭제됐어요",
                              style: TextStyle(
                                fontWeight: read
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                              ),
                            )
                          : isHiddenNotice
                          ? Text(
                              "'$itemTitle' 게시글이 신고 검토 후 숨김 처리됐어요",
                              style: TextStyle(
                                fontWeight: read
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                              ),
                            )
                          : isReportResult
                          ? Text(
                              "신고해주신 '$itemTitle' 게시글이 처리됐어요",
                              style: TextStyle(
                                fontWeight: read
                                    ? FontWeight.w500
                                    : FontWeight.w700,
                              ),
                            )
                          : isKeywordMatch
                          ? Text(
                              matchType == 'category'
                                  ? "구독한 카테고리 '$keyword'에 새 글이 등록됐어요"
                                  : "저장한 키워드 '$keyword'와 일치하는 글이 등록됐어요",
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
                      subtitle: isRemovedNotice
                          ? const Text(
                              '커뮤니티 정책에 따라 삭제되었어요',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : isHiddenNotice
                          ? const Text(
                              '마이페이지 > 내 글에서 확인할 수 있어요',
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            )
                          : isReportResult
                          ? const Text(
                              '신고해주셔서 감사합니다',
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
                            if (!context.mounted) return;
                            await _deleteNotification(context, doc);
                          }
                        },
                      ),
                      onTap: () => _openNotification(context, doc),
                    ),
                  ),
                );
              },
            ),
          );
        },
      ),
    );
  }
}
