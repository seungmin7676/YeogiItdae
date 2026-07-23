import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:share_plus/share_plus.dart';

import '../models/lost_found_item.dart';
import '../services/analytics_service.dart';
import '../services/error_messages.dart';
import '../services/image_save_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_user_data.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/item_card.dart';
import 'author_posts_screen.dart';
import 'chat_screen.dart';
import 'register_item_screen.dart';

/// 게시글 상세를 바텀시트로 연다. 홈 피드·내 글·작성자 글·찜한 글·알림
/// 화면에서 완전히 동일한 방식으로 열길래 한 곳에 모았다.
void showItemDetailSheet(BuildContext context, LostFoundItem item) {
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.surface,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusXl)),
    ),
    builder: (context) => ItemDetailSheet(item: item),
  );
}

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
      borderRadius: BorderRadius.circular(kRadiusLg),
      child: SizedBox(
        height: 240,
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              onPageChanged: (index) => setState(() => _page = index),
              itemCount: widget.imageUrls.length,
              itemBuilder: (context, index) => GestureDetector(
                onTap: () =>
                    _openFullScreenGallery(context, widget.imageUrls, index),
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrls[index],
                  width: double.infinity,
                  height: 240,
                  fit: BoxFit.cover,
                  placeholder: (context, url) => Container(
                    width: double.infinity,
                    height: 240,
                    color: AppColors.surfaceAlt,
                    alignment: Alignment.center,
                    child: const CircularProgressIndicator(
                      color: AppColors.primary,
                      strokeWidth: 2.5,
                    ),
                  ),
                  errorWidget: (context, url, error) => Container(
                    width: double.infinity,
                    height: 240,
                    color: AppColors.surfaceAlt,
                    child: const Icon(
                      Icons.broken_image_outlined,
                      color: AppColors.inkFaint,
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
                    borderRadius: BorderRadius.circular(kRadiusSm),
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
                child: CachedNetworkImage(
                  imageUrl: widget.imageUrls[index],
                  placeholder: (context, url) =>
                      const CircularProgressIndicator(
                        color: Colors.white,
                        strokeWidth: 2.5,
                      ),
                  errorWidget: (context, url, error) => const Icon(
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
                      borderRadius: BorderRadius.circular(kRadiusSm),
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
    final metaParts = [
      if (item.createdAt != null) relativeTime(item.createdAt),
      '조회 ${item.viewCount}',
    ];
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      // 내용이 길어도 넘치지 않도록 본문은 스크롤 영역에, 핵심 행동(채팅하기/
      // 수정·삭제)은 하단 고정 영역에 둔다.
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.88,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(kPagePadding, 10, 8, 0),
              child: Stack(
                alignment: Alignment.center,
                children: [
                  Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: AppColors.lineStrong,
                      borderRadius: BorderRadius.circular(2),
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
            ),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(
                  kPagePadding,
                  10,
                  kPagePadding,
                  16,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (item.imageUrls.isNotEmpty) ...[
                      _ImageGallery(imageUrls: item.imageUrls),
                      const SizedBox(height: 18),
                    ],
                    Row(
                      children: [
                        StatusBadge(type: item.type),
                        const SizedBox(width: 8),
                        Text(
                          item.category,
                          style: const TextStyle(
                            fontSize: 12.5,
                            color: AppColors.inkMuted,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        if (item.resolved) ...[
                          const SizedBox(width: 8),
                          const SoftBadge(
                            label: '거래완료',
                            color: AppColors.inkMuted,
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 10),
                    Text(
                      item.title,
                      style: const TextStyle(
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        letterSpacing: -0.6,
                        height: 1.28,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Text(
                      metaParts.join(' · '),
                      style: const TextStyle(
                        fontSize: 12.5,
                        color: AppColors.inkFaint,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                    if (item.description.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      Text(
                        item.description,
                        style: const TextStyle(
                          fontSize: 15,
                          height: 1.65,
                          color: AppColors.ink,
                        ),
                      ),
                    ],
                    const SizedBox(height: 20),
                    const Divider(),
                    const SizedBox(height: 16),
                    _DetailRow(
                      icon: Icons.place_outlined,
                      label: item.type == ItemType.found ? '발견 장소' : '분실 장소',
                      value: item.locationDetail.isEmpty
                          ? item.location
                          : '${item.location} (${item.locationDetail})',
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
                  ],
                ),
              ),
            ),
            Container(
              width: double.infinity,
              decoration: const BoxDecoration(
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              padding: const EdgeInsets.fromLTRB(
                kPagePadding,
                12,
                kPagePadding,
                12,
              ),
              child: SafeArea(
                top: false,
                child: Builder(
                  builder: (context) {
                    final currentUid = FirebaseAuth.instance.currentUser?.uid;
                    final isOwner =
                        currentUid == item.authorUid &&
                        item.authorUid.isNotEmpty;

                    if (!isOwner) {
                      final hasBlocked = AppUserData.of(
                        context,
                      ).blockedUids.contains(item.authorUid);

                      if (hasBlocked) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: AppColors.line,
                            borderRadius: BorderRadius.circular(kRadiusMd),
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
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        if (item.isHidden && item.id != null)
                          _ReportAppealSection(
                            itemId: item.id!,
                            itemTitle: item.title,
                          ),
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
                                  side: const BorderSide(
                                    color: AppColors.danger,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    );
                  },
                ),
              ),
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
      // 채팅 목록(list) 규칙은 "결과가 전부 본인이 참여한 채팅"임을 쿼리
      // 조건만으로 증명해야 하므로 participants 필터가 반드시 필요하다.
      // 작성자는 이 글의 모든 채팅방 참여자라 결과는 동일하다.
      final relatedChats = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: item.authorUid)
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('처리하지 못했습니다: ${friendlyErrorMessage(e)}')),
        );
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
    final confirmed = await showConfirmDialog(
      context,
      title: '게시글 삭제',
      content: '이 게시글을 삭제하시겠습니까? 삭제 후에는 되돌릴 수 없습니다.',
      confirmLabel: '삭제',
      danger: true,
      haptic: true,
    );
    if (!confirmed) return;
    if (!context.mounted || _isProcessing) return;

    setState(() => _isProcessing = true);
    final navigator = Navigator.of(context);
    try {
      // 게시글을 지우기 전에, 이 글로 진행 중이던 채팅방들에 먼저
      // "게시글 삭제됨" 표시를 남긴다. 그렇지 않으면 채팅방에 남아있는
      // 거래완료 확인/처리 버튼이 이미 사라진 게시글 문서를 업데이트하려다
      // 실패해 사용자에게 원인을 알 수 없는 오류만 보여주게 된다.
      // list 규칙 증명을 위해 participants 필터가 필요하다(_markResolved와
      // 동일한 이유). 작성자는 이 글의 모든 채팅방 참여자라 결과는 동일하다.
      final relatedChats = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: item.authorUid)
          .where('itemId', isEqualTo: item.id)
          .get();
      if (relatedChats.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final chatDoc in relatedChats.docs) {
          batch.set(chatDoc.reference, {
            'itemDeleted': true,
          }, SetOptions(merge: true));
        }
        await batch.commit();
      }

      await itemsCollection.doc(item.id).delete();
      navigator.pop();
    } catch (e) {
      if (mounted) setState(() => _isProcessing = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('삭제하지 못했습니다: ${friendlyErrorMessage(e)}')),
        );
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
        logChatStarted();
      }
    } catch (e) {
      if (mounted) setState(() => _isProcessing = false);
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('채팅을 시작하지 못했습니다: ${friendlyErrorMessage(e)}')),
        );
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('찜 처리에 실패했습니다: ${friendlyErrorMessage(e)}')),
        );
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
        Icon(icon, size: 17, color: AppColors.inkFaint),
        const SizedBox(width: 10),
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: const TextStyle(
              fontSize: 13.5,
              color: AppColors.inkMuted,
              fontWeight: FontWeight.w500,
            ),
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
            ),
          ),
        ),
        if (onTap != null)
          const Icon(
            Icons.chevron_right_rounded,
            size: 18,
            color: AppColors.inkFaint,
          ),
      ],
    );
    if (onTap == null) return row;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(kRadiusSm),
      child: row,
    );
  }
}

/// 신고 누적으로 숨김 처리된 게시글에서 작성자에게 보여주는 이의제기 영역.
/// 검토·해제는 클라이언트/자동화 없이 관리자가 Firebase 콘솔에서 직접
/// reportAppeals 문서를 보고 판단하는 최소 기능이다.
class _ReportAppealSection extends StatefulWidget {
  final String itemId;
  final String itemTitle;

  const _ReportAppealSection({required this.itemId, required this.itemTitle});

  @override
  State<_ReportAppealSection> createState() => _ReportAppealSectionState();
}

class _ReportAppealSectionState extends State<_ReportAppealSection> {
  bool _isSubmitting = false;

  Future<void> _submitAppeal(BuildContext context) async {
    final reasonController = TextEditingController();
    final reason = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusMd),
        ),
        title: const Text('이의제기'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              '신고가 누적되어 이 게시글이 자동으로 숨겨졌어요.\n부당하다고 생각되면 사유를 남겨주세요.',
              style: TextStyle(
                color: AppColors.inkMuted,
                fontSize: 12.5,
                height: 1.4,
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: reasonController,
              autofocus: true,
              maxLines: 3,
              decoration: const InputDecoration(hintText: '이의제기 사유를 입력해주세요'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () =>
                Navigator.pop(dialogContext, reasonController.text.trim()),
            child: const Text('제출'),
          ),
        ],
      ),
    );
    if (reason == null || reason.isEmpty || !context.mounted) return;

    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    setState(() => _isSubmitting = true);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('reportAppeals')
          .doc(widget.itemId)
          .set({
            'itemId': widget.itemId,
            'itemTitle': widget.itemTitle,
            'authorUid': myUid,
            'reason': reason,
            'status': 'pending',
            'createdAt': FieldValue.serverTimestamp(),
          });
      messenger.showSnackBar(
        const SnackBar(content: Text('이의제기를 접수했어요. 검토 후 처리해드릴게요.')),
      );
    } on FirebaseException catch (e) {
      final message = e.code == 'permission-denied'
          ? '이미 이의제기를 접수한 게시글입니다.'
          : '이의제기 접수에 실패했습니다: ${e.message}';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('이의제기 접수에 실패했습니다: ${friendlyErrorMessage(e)}')),
      );
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('reportAppeals')
          .doc(widget.itemId)
          .snapshots(),
      builder: (context, snapshot) {
        final alreadySubmitted = snapshot.data?.exists ?? false;
        return Container(
          width: double.infinity,
          margin: const EdgeInsets.only(bottom: 12),
          padding: const EdgeInsets.all(14),
          decoration: BoxDecoration(
            color: AppColors.danger.withValues(alpha: 0.06),
            borderRadius: BorderRadius.circular(kRadiusMd),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Row(
                children: [
                  Icon(
                    Icons.visibility_off_outlined,
                    size: 18,
                    color: AppColors.danger,
                  ),
                  SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      '신고 누적으로 숨김 처리된 게시글이에요',
                      style: TextStyle(
                        fontWeight: FontWeight.w700,
                        color: AppColors.danger,
                        fontSize: 13,
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              if (alreadySubmitted)
                const Text(
                  '이의제기가 접수되어 검토 중이에요.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
                )
              else
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton(
                    onPressed: _isSubmitting
                        ? null
                        : () => _submitAppeal(context),
                    style: OutlinedButton.styleFrom(
                      foregroundColor: AppColors.danger,
                      side: const BorderSide(color: AppColors.danger),
                    ),
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Text('부당한 신고라면 이의제기하기'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}
