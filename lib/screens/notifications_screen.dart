import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/lost_found_item.dart';
import '../theme/app_theme.dart';
import '../widgets/count_badge.dart';
import '../widgets/feed_message.dart';
import 'chat_screen.dart';
import 'item_detail_sheet.dart';

/// 알림 종류(type)에 대응하는 userSettings 필드. 필드가 없으면 기본값은 켜짐이다.
const Map<String, String> _kNotificationTypeToSettingField = {
  'chat_started': 'notifyChatStarted',
  'keyword_match': 'notifyKeywordMatch',
  'report_result': 'notifyReportResult',
  'item_hidden': 'notifyItemHidden',
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
        return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
          stream: FirebaseFirestore.instance
              .collection('userSettings')
              .doc(uid ?? '_')
              .snapshots(),
          builder: (context, settingsSnapshot) {
            final settings = settingsSnapshot.data?.data() ?? const {};
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
                      return !blockedUids.contains(senderUid) &&
                          _isNotificationTypeEnabled(settings, type);
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

class _NotificationsScreenState extends State<NotificationsScreen> {
  /// 삭제는 Firestore 서버 응답을 받아야 목록에서 실제로 빠지는데,
  /// Dismissible은 onDismissed가 끝난 다음 프레임에 위젯이 트리에서
  /// 사라져 있기를 기대한다(그렇지 않으면 "A dismissed Dismissible widget
  /// is still part of the tree" 오류). 서버 응답을 기다리지 않고 로컬에서
  /// 즉시 감춰서 이 타이밍 문제를 없앤다. 삭제가 실패하면 다시 보이게
  /// 되돌린다.
  final Set<String> _locallyDeletedIds = {};

  Future<void> _deleteNotification(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    setState(() => _locallyDeletedIds.add(doc.id));
    try {
      await doc.reference.delete();
    } catch (e) {
      if (mounted) setState(() => _locallyDeletedIds.remove(doc.id));
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('알림 삭제에 실패했습니다: $e')));
      }
    }
  }

  Future<void> _openNotification(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    await doc.reference.update({'read': true});
    if (!context.mounted) return;
    final type = data['type'] as String? ?? 'chat_started';

    if (type == 'keyword_match') {
      final itemId = data['itemId'] as String?;
      if (itemId == null) return;
      final itemDoc = await itemsCollection.doc(itemId).get();
      if (!context.mounted || !itemDoc.exists) return;
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: Colors.white,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (context) =>
            ItemDetailSheet(item: LostFoundItem.fromDoc(itemDoc)),
      );
      return;
    }
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

  Future<void> _markAllRead(BuildContext context, String? uid) async {
    if (uid == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final unread = await FirebaseFirestore.instance
        .collection('notifications')
        .where('recipientUid', isEqualTo: uid)
        .where('read', isEqualTo: false)
        .get();
    if (unread.docs.isEmpty) {
      messenger.showSnackBar(const SnackBar(content: Text('읽지 않은 알림이 없어요.')));
      return;
    }
    final batch = FirebaseFirestore.instance.batch();
    for (final doc in unread.docs) {
      batch.update(doc.reference, {'read': true});
    }
    await batch.commit();
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
        actions: [
          TextButton(
            onPressed: () => _markAllRead(context, uid),
            child: const Text('모두 읽음'),
          ),
        ],
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
          return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('userSettings')
                .doc(uid ?? '_')
                .snapshots(),
            builder: (context, settingsSnapshot) {
              final settings = settingsSnapshot.data?.data() ?? const {};
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
                      child: CircularProgressIndicator(
                        color: AppColors.primary,
                      ),
                    );
                  }

                  // 내가 차단한 사용자가 보낸 알림은 차단 사실이 드러나지 않도록
                  // 완전히 걸러내고, 알림 설정에서 꺼둔 종류와 방금 로컬에서
                  // 삭제한(아직 서버 확인 전인) 항목도 함께 제외한다
                  // (메시지·채팅 목록과 동일한 원칙 — 알림 자체는 계속 만들어지지만
                  // 본인 화면에서만 걸러진다).
                  final docs = snapshot.data!.docs.where((doc) {
                    if (_locallyDeletedIds.contains(doc.id)) return false;
                    final data = doc.data();
                    final senderUid = data['senderUid'] as String?;
                    final type = data['type'] as String? ?? 'chat_started';
                    return !blockedUids.contains(senderUid) &&
                        _isNotificationTypeEnabled(settings, type);
                  }).toList();

                  // 서버가 삭제를 확정한 뒤에도(문서가 스냅샷에서 완전히
                  // 사라진 뒤에도) _locallyDeletedIds에 계속 남아있지 않도록
                  // 정리한다.
                  final stillPresentIds = snapshot.data!.docs
                      .map((doc) => doc.id)
                      .toSet();
                  final staleIds = _locallyDeletedIds.difference(
                    stillPresentIds,
                  );
                  if (staleIds.isNotEmpty) {
                    WidgetsBinding.instance.addPostFrameCallback((_) {
                      if (mounted) {
                        setState(() => _locallyDeletedIds.removeAll(staleIds));
                      }
                    });
                  }

                  if (docs.isEmpty) {
                    return const FeedMessage(
                      icon: Icons.notifications_none_rounded,
                      text: '알림이 없어요.',
                    );
                  }

                  return RefreshIndicator(
                    color: AppColors.primary,
                    onRefresh: () => FirebaseFirestore.instance
                        .collection('notifications')
                        .where('recipientUid', isEqualTo: uid)
                        .orderBy('createdAt', descending: true)
                        .get(const GetOptions(source: Source.server)),
                    child: ListView.builder(
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
                        final keyword = data['keyword'] as String? ?? '';
                        final matchType =
                            data['matchType'] as String? ?? 'keyword';
                        final type = data['type'] as String? ?? 'chat_started';
                        final isHiddenNotice = type == 'item_hidden';
                        final isReportResult = type == 'report_result';
                        final isKeywordMatch = type == 'keyword_match';

                        return Dismissible(
                          key: ValueKey(doc.id),
                          direction: DismissDirection.endToStart,
                          confirmDismiss: (_) => _confirmDelete(context),
                          onDismissed: (_) => _deleteNotification(context, doc),
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
                                    : isReportResult
                                    ? Icons.flag_outlined
                                    : isKeywordMatch
                                    ? Icons.notifications_active_outlined
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
                                            profileSnapshot.data
                                                    ?.data()?['nickname']
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
              );
            },
          );
        },
      ),
    );
  }
}
