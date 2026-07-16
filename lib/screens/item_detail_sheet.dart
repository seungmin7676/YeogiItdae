import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

import '../models/lost_found_item.dart';
import '../services/image_save_service.dart';
import '../theme/app_theme.dart';
import '../widgets/item_card.dart';
import 'author_posts_screen.dart';
import 'chat_screen.dart';
import 'register_item_screen.dart';

/// 상세보기 상단의 사진 갤러리 (여러 장이면 스와이프 + 페이지 표시).
class _ImageGallery extends StatefulWidget {
  final List<String> imageUrls;

  const _ImageGallery({required this.imageUrls});

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 210,
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              onPageChanged: (index) => setState(() => _page = index),
              itemCount: widget.imageUrls.length,
              itemBuilder: (context, index) => GestureDetector(
                onTap: () =>
                    _openFullScreenGallery(context, widget.imageUrls, index),
                child: Image.network(
                  widget.imageUrls[index],
                  width: double.infinity,
                  height: 210,
                  fit: BoxFit.cover,
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return Container(
                      width: double.infinity,
                      height: 210,
                      color: AppColors.bg,
                      alignment: Alignment.center,
                      child: const CircularProgressIndicator(
                        color: AppColors.primary,
                        strokeWidth: 2.5,
                      ),
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => Container(
                    width: double.infinity,
                    height: 210,
                    color: AppColors.bg,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: Color(0xFFC7CAD6),
                      size: 40,
                    ),
                  ),
                ),
              ),
            ),
            if (widget.imageUrls.length > 1)
              Positioned(
                bottom: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_page + 1}/${widget.imageUrls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 사진을 탭하면 핀치 줌이 가능한 전체화면 뷰어로 확대해서 본다
/// (채팅방 이미지 뷰어와 동일한 방식).
void _openFullScreenGallery(
  BuildContext context,
  List<String> imageUrls,
  int initialIndex,
) {
  showDialog<void>(
    context: context,
    barrierColor: Colors.black,
    builder: (dialogContext) =>
        _FullScreenGallery(imageUrls: imageUrls, initialIndex: initialIndex),
  );
}

class _FullScreenGallery extends StatefulWidget {
  final List<String> imageUrls;
  final int initialIndex;

  const _FullScreenGallery({
    required this.imageUrls,
    required this.initialIndex,
  });

  @override
  State<_FullScreenGallery> createState() => _FullScreenGalleryState();
}

class _FullScreenGalleryState extends State<_FullScreenGallery> {
  late final _controller = PageController(initialPage: widget.initialIndex);
  late int _page = widget.initialIndex;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      body: Stack(
        children: [
          PageView.builder(
            controller: _controller,
            onPageChanged: (index) => setState(() => _page = index),
            itemCount: widget.imageUrls.length,
            itemBuilder: (context, index) => InteractiveViewer(
              child: Center(
                child: Image.network(
                  widget.imageUrls[index],
                  loadingBuilder: (context, child, progress) {
                    if (progress == null) return child;
                    return const CircularProgressIndicator(
                      color: Colors.white,
                      strokeWidth: 2.5,
                    );
                  },
                  errorBuilder: (context, error, stackTrace) => const Icon(
                    Icons.broken_image_outlined,
                    color: Colors.white54,
                    size: 48,
                  ),
                ),
              ),
            ),
          ),
          SafeArea(
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(
                  icon: const Icon(Icons.close, color: Colors.white),
                  tooltip: '닫기',
                  onPressed: () => Navigator.pop(context),
                ),
                IconButton(
                  icon: const Icon(
                    Icons.download_outlined,
                    color: Colors.white,
                  ),
                  tooltip: '사진 저장',
                  onPressed: () =>
                      saveImageToDevice(context, widget.imageUrls[_page]),
                ),
              ],
            ),
          ),
          if (widget.imageUrls.length > 1)
            SafeArea(
              child: Align(
                alignment: Alignment.topCenter,
                child: Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.white.withValues(alpha: 0.15),
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${_page + 1}/${widget.imageUrls.length}',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 화면 C: 상세 보기 BottomSheet
class ItemDetailSheet extends StatefulWidget {
  final LostFoundItem item;

  const ItemDetailSheet({super.key, required this.item});

  @override
  State<ItemDetailSheet> createState() => _ItemDetailSheetState();
}

class _ItemDetailSheetState extends State<ItemDetailSheet> {
  // 채팅하기/거래완료로 표시/삭제 버튼의 연속 탭으로 인한 중복 요청을 막는다.
  bool _isProcessing = false;
  Timer? _relativeTimeTimer;

  LostFoundItem get item => widget.item;

  @override
  void initState() {
    super.initState();
    if (item.createdAt != null) {
      // "n분 전" 같은 상대시간 표시가 시트를 오래 열어둬도 계속 최신 상태를
      // 유지하도록 주기적으로 다시 그린다.
      _relativeTimeTimer = Timer.periodic(const Duration(minutes: 1), (_) {
        if (mounted) setState(() {});
      });
    }
  }

  @override
  void dispose() {
    _relativeTimeTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Align(
                  alignment: Alignment.centerRight,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(
                          Icons.share_outlined,
                          size: 20,
                          color: AppColors.inkMuted,
                        ),
                        tooltip: '공유하기',
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _shareItem(context),
                      ),
                      if (FirebaseAuth.instance.currentUser?.uid != null &&
                          FirebaseAuth.instance.currentUser!.uid !=
                              item.authorUid) ...[
                        if (item.id != null) _BookmarkButton(item: item),
                        IconButton(
                          icon: const Icon(
                            Icons.flag_outlined,
                            size: 20,
                            color: AppColors.inkMuted,
                          ),
                          tooltip: '신고하기',
                          visualDensity: VisualDensity.compact,
                          onPressed: () => _reportItem(context),
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (item.imageUrls.isNotEmpty) ...[
              _ImageGallery(imageUrls: item.imageUrls),
              const SizedBox(height: 18),
            ],
            Row(
              children: [
                StatusBadge(type: item.type),
                if (item.resolved) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDEEF3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '거래완료',
                      style: TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              item.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 16),
            if (item.description.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  item.description,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            _DetailRow(
              icon: Icons.place_outlined,
              label: item.type == ItemType.found ? '발견 장소' : '분실 장소',
              value: item.locationDetail.isEmpty
                  ? item.location
                  : '${item.location} (${item.locationDetail})',
            ),
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.label_outline,
              label: '글 종류',
              value: item.type == ItemType.found
                  ? '습득물 (주웠어요)'
                  : '분실물 (잃어버렸어요)',
            ),
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.category_outlined,
              label: '카테고리',
              value: item.category,
            ),
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.person_outline,
              label: '작성자',
              value: item.authorNickname,
              onTap: () => Navigator.push(
                context,
                MaterialPageRoute(
                  builder: (context) => AuthorPostsScreen(
                    authorUid: item.authorUid,
                    authorNickname: item.authorNickname,
                  ),
                ),
              ),
            ),
            if (item.createdAt != null) ...[
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.schedule_outlined,
                label: '등록일',
                value: relativeTime(item.createdAt),
              ),
            ],
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.visibility_outlined,
              label: '조회수',
              value: '${item.viewCount}회',
            ),
            const SizedBox(height: 32),
            Builder(
              builder: (context) {
                final currentUid = FirebaseAuth.instance.currentUser?.uid;
                final isOwner =
                    currentUid == item.authorUid && item.authorUid.isNotEmpty;

                if (!isOwner) {
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('blocks')
                        .doc(currentUid ?? '_')
                        .snapshots(),
                    builder: (context, snapshot) {
                      final blockedUsers = Map<String, dynamic>.from(
                        snapshot.data?.data()?['blockedUsers'] as Map? ?? {},
                      );
                      final hasBlocked = blockedUsers.containsKey(
                        item.authorUid,
                      );

                      if (hasBlocked) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: AppColors.line,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          alignment: Alignment.center,
                          child: const Text(
                            '차단한 사용자입니다',
                            style: TextStyle(color: AppColors.inkMuted),
                          ),
                        );
                      }

                      return SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: _isProcessing
                              ? null
                              : () => _startChat(context),
                          icon: _isProcessing
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.chat_bubble_outline),
                          label: const Text('채팅하기'),
                        ),
                      );
                    },
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!item.resolved)
                      OutlinedButton.icon(
                        onPressed: _isProcessing
                            ? null
                            : () => _markResolved(context),
                        icon: _isProcessing
                            ? const SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.primary,
                                ),
                              )
                            : const Icon(Icons.check_circle_outline),
                        label: const Text('거래완료로 표시'),
                        style: OutlinedButton.styleFrom(
                          foregroundColor: AppColors.primary,
                          side: const BorderSide(color: AppColors.primary),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isProcessing
                                ? null
                                : () => _editItem(context),
                            icon: const Icon(Icons.edit_outlined),
                            label: const Text('수정'),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: OutlinedButton.icon(
                            onPressed: _isProcessing
                                ? null
                                : () => _confirmDelete(context),
                            icon: _isProcessing
                                ? const SizedBox(
                                    width: 16,
                                    height: 16,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2,
                                      color: AppColors.danger,
                                    ),
                                  )
                                : const Icon(Icons.delete_outline),
                            label: const Text('삭제'),
                            style: OutlinedButton.styleFrom(
                              foregroundColor: AppColors.danger,
                              side: const BorderSide(color: AppColors.danger),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _shareItem(BuildContext context) async {
    final typeLabel = item.type == ItemType.found ? '습득물' : '분실물';
    final location = item.locationDetail.isEmpty
        ? item.location
        : '${item.location} (${item.locationDetail})';
    final text =
        '[여기있대! - 한림대 분실물 게시판]\n'
        '$typeLabel: ${item.title}\n'
        '장소: $location\n'
        '카테고리: ${item.category}'
        '${item.description.isEmpty ? '' : '\n\n${item.description}'}';

    final box = context.findRenderObject() as RenderBox?;
    await SharePlus.instance.share(
      ShareParams(
        text: text,
        sharePositionOrigin: box != null
            ? box.localToGlobal(Offset.zero) & box.size
            : null,
      ),
    );
  }

  Future<void> _reportItem(BuildContext context) async {
    const reasons = ['부적절한 내용', '스팸/광고', '사기 의심', '기타'];
    String selectedReason = reasons.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('게시글 신고하기'),
              content: RadioGroup<String>(
                groupValue: selectedReason,
                onChanged: (value) {
                  setDialogState(() => selectedReason = value!);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: reasons
                      .map(
                        (reason) => RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: Text(reason),
                          value: reason,
                        ),
                      )
                      .toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('취소'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('신고'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    try {
      final reportRef = FirebaseFirestore.instance
          .collection('reports')
          .doc('${item.id}_$myUid');
      final itemRef = itemsCollection.doc(item.id);

      // 트랜잭션으로 처리해 "이번 신고가 자동 숨김 기준을 막 넘겼는지"를
      // 정확히 판단하고, 그 경우에만 작성자에게 알림을 한 번 보낸다.
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final itemSnap = await transaction.get(itemRef);
        final currentCount =
            (itemSnap.data()?['reportCount'] as num?)?.toInt() ?? 0;

        transaction.set(reportRef, {
          'itemId': item.id,
          'reporterUid': myUid,
          'reason': selectedReason,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(itemRef, {'reportCount': FieldValue.increment(1)});

        if (currentCount < kReportThreshold &&
            currentCount + 1 >= kReportThreshold) {
          transaction.set(
            FirebaseFirestore.instance.collection('notifications').doc(),
            {
              'recipientUid': item.authorUid,
              'senderUid': myUid,
              'type': 'item_hidden',
              'itemId': item.id,
              'itemTitle': item.title,
              'read': false,
              'createdAt': FieldValue.serverTimestamp(),
            },
          );
          // 이번 신고로 숨김 기준을 넘겼다면, 신고자에게도 처리 결과를 알려준다.
          transaction.set(
            FirebaseFirestore.instance.collection('notifications').doc(),
            {
              'recipientUid': myUid,
              'senderUid': myUid,
              'type': 'report_result',
              'itemId': item.id,
              'itemTitle': item.title,
              'read': false,
              'createdAt': FieldValue.serverTimestamp(),
            },
          );
        }
      });
      messenger.showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다.')));
    } on FirebaseException catch (e) {
      final message = e.code == 'permission-denied'
          ? '이미 신고한 게시글입니다.'
          : '신고를 접수하지 못했습니다: ${e.message}';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _markResolved(BuildContext context) async {
    if (_isProcessing) return;
    setState(() => _isProcessing = true);
    final navigator = Navigator.of(context);
    try {
      await itemsCollection.doc(item.id).update({'resolved': true});

      // 이 글로 진행 중이던 모든 채팅의 거래완료 상태도 함께 맞춰서,
      // "상대방 확인 대기 중" 배너가 채팅방에 그대로 남아있지 않도록 한다.
      final relatedChats = await FirebaseFirestore.instance
          .collection('chats')
          .where('itemId', isEqualTo: item.id)
          .get();
      if (relatedChats.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final chatDoc in relatedChats.docs) {
          batch.set(chatDoc.reference, {
            'resolutionStatus': 'done',
          }, SetOptions(merge: true));
        }
        await batch.commit();
      }

      navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _isProcessing = false);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('처리하지 못했습니다: $e')));
      }
    }
  }

  void _editItem(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(
        builder: (context) => RegisterItemScreen(editingItem: item),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('게시글 삭제'),
        content: const Text('이 게시글을 삭제하시겠습니까? 삭제 후에는 되돌릴 수 없습니다.'),
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
            child: const Text('삭제', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted || _isProcessing) return;

    setState(() => _isProcessing = true);
    final navigator = Navigator.of(context);
    try {
      await itemsCollection.doc(item.id).delete();
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _isProcessing = false);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('삭제하지 못했습니다: $e')));
      }
    }
  }

  Future<void> _startChat(BuildContext context) async {
    if (_isProcessing) return;
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || item.id == null) return;

    if (item.authorUid == currentUser.uid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('본인이 등록한 게시글입니다.')));
      return;
    }

    setState(() => _isProcessing = true);
    final uids = [currentUser.uid, item.authorUid]..sort();
    final chatId = '${item.id}_${uids.join('_')}';
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);

    final navigator = Navigator.of(context);

    try {
      final snap = await chatRef.get();
      if (!snap.exists) {
        await chatRef.set({
          'participants': uids,
          'participantNicknames': {
            currentUser.uid: currentUser.displayName ?? '익명',
            item.authorUid: item.authorNickname,
          },
          'itemId': item.id,
          'itemTitle': item.title,
          'itemAuthorUid': item.authorUid,
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastReadAt': {currentUser.uid: FieldValue.serverTimestamp()},
          'unreadCount': {currentUser.uid: 0, item.authorUid: 0},
          'resolutionStatus': 'none',
        });

        await FirebaseFirestore.instance.collection('notifications').add({
          'recipientUid': item.authorUid,
          'senderUid': currentUser.uid,
          'senderNickname': currentUser.displayName ?? '익명',
          'type': 'chat_started',
          'itemId': item.id,
          'itemTitle': item.title,
          'chatId': chatId,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      if (mounted) setState(() => _isProcessing = false);
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('채팅을 시작하지 못했습니다: $e')));
      }
      return;
    }

    navigator.pop();
    navigator.push(
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          chatId: chatId,
          itemTitle: item.title,
          otherNickname: item.authorNickname,
          otherUid: item.authorUid,
        ),
      ),
    );
  }
}

/// 게시글 상세 상단의 찜(관심글 저장) 토글 버튼.
class _BookmarkButton extends StatelessWidget {
  final LostFoundItem item;

  const _BookmarkButton({required this.item});

  Future<void> _toggle(BuildContext context, bool isSaved) async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    final ref = FirebaseFirestore.instance.collection('bookmarks').doc(myUid);
    try {
      if (isSaved) {
        await ref.set({
          'itemIds': FieldValue.arrayRemove([item.id]),
        }, SetOptions(merge: true));
      } else {
        await ref.set({
          'itemIds': FieldValue.arrayUnion([item.id]),
        }, SetOptions(merge: true));
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('찜 처리에 실패했습니다: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('bookmarks')
          .doc(myUid ?? '_')
          .snapshots(),
      builder: (context, snapshot) {
        final itemIds = List<String>.from(
          snapshot.data?.data()?['itemIds'] as List? ?? const [],
        );
        final isSaved = itemIds.contains(item.id);
        return IconButton(
          icon: Icon(
            isSaved ? Icons.bookmark_rounded : Icons.bookmark_border_rounded,
            size: 20,
            color: isSaved ? AppColors.primary : AppColors.inkMuted,
          ),
          tooltip: isSaved ? '찜 해제' : '찜하기',
          visualDensity: VisualDensity.compact,
          onPressed: () => _toggle(context, isSaved),
        );
      },
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;
  final VoidCallback? onTap;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final row = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.inkMuted),
        const SizedBox(width: 8),
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: onTap != null ? AppColors.primary : AppColors.ink,
              decoration: onTap != null ? TextDecoration.underline : null,
              decorationColor: AppColors.primary,
            ),
          ),
        ),
      ],
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}
