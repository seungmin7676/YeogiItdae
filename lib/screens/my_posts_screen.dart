import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/lost_found_item.dart';
import '../services/bulk_item_actions.dart';
import '../services/item_queries.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/feed_message.dart';
import '../widgets/item_card.dart';
import '../widgets/skeleton.dart';
import 'item_detail_sheet.dart';
import 'register_item_screen.dart';

/// 화면: 내가 등록한 글 모아보기
class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({super.key});

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  int _limit = kInitialPageLimit;

  /// 필터·정렬이 바뀌면 이전 기준으로 늘려둔 개수를 처음으로 되돌린다.
  void _resetPaging() => _limit = kInitialPageLimit;

  // 상태 필터: 0 = 전체, 1 = 진행중, 2 = 거래완료
  int _statusFilter = 0;
  // 정렬 기준: false = 최신순, true = 오래된순
  bool _sortOldestFirst = false;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  // 일괄 작업(거래완료/삭제)이 진행 중인지. 버튼 연타·중복 다이얼로그로
  // 같은 작업이 두 번 실행되는 것을 UI 계층에서 막는다. (서비스 계층의
  // in-flight 방어와 이중 안전장치)
  bool _isBulkWorking = false;
  final BulkItemActions _bulkActions = BulkItemActions(itemsCollection);

  Query<Map<String, dynamic>> _query(String? uid) => buildMyPostsQuery(
    collection: itemsCollection,
    uid: uid,
    statusFilter: _statusFilter,
    oldestFirst: _sortOldestFirst,
    limit: _limit,
  );

  void _endSelectionMode() {
    setState(() {
      _selectionMode = false;
      _selectedIds.clear();
    });
  }

  void _toggleSelected(String id) {
    setState(() {
      if (_selectedIds.contains(id)) {
        _selectedIds.remove(id);
      } else {
        _selectedIds.add(id);
      }
      if (_selectedIds.isEmpty) _selectionMode = false;
    });
  }

  void _enterSelectionMode(String id) {
    setState(() {
      _selectionMode = true;
      _selectedIds.add(id);
    });
  }

  /// 일괄 작업 결과를 선택 상태에 반영한다. 성공했거나 이미 삭제된 글만
  /// 선택 해제하고, 실패한 글은 선택 상태로 남겨 그대로 재시도할 수 있게 한다.
  void _applyBulkResult(BulkActionResult result, String verb) {
    setState(() {
      _selectedIds.removeAll(result.succeeded);
      _selectedIds.removeAll(result.notFound);
      if (_selectedIds.isEmpty) _selectionMode = false;
    });

    final parts = <String>[
      if (result.succeeded.isNotEmpty) '${result.succeeded.length}개를 $verb했어요.',
      if (result.notFound.isNotEmpty)
        '${result.notFound.length}개는 이미 삭제된 글이에요.',
      if (result.hasFailures)
        '${result.failed.length}개는 처리하지 못했어요. 선택 상태로 남겨두었으니 다시 시도해주세요.',
    ];
    if (parts.isNotEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(parts.join(' '))));
    }
  }

  Future<void> _bulkMarkResolved() async {
    if (_isBulkWorking || _selectedIds.isEmpty) return;
    setState(() => _isBulkWorking = true);
    try {
      final confirmed = await showConfirmDialog(
        context,
        title: '거래완료 처리',
        content: '선택한 ${_selectedIds.length}개의 글을 거래완료로 처리하시겠습니까?',
        confirmLabel: '완료 처리',
      );
      if (!confirmed || !mounted) return;

      final result = await _bulkActions.markResolved(_selectedIds);
      if (!mounted) return;
      _applyBulkResult(result, '거래완료로 처리');
    } finally {
      // 오류가 나더라도 버튼이 영구적으로 잠기지 않도록 항상 복구한다.
      if (mounted) setState(() => _isBulkWorking = false);
    }
  }

  Future<void> _bulkDelete() async {
    if (_isBulkWorking || _selectedIds.isEmpty) return;
    // 다이얼로그가 뜨기 전 연속 탭으로 확인 다이얼로그가 겹쳐 쌓여
    // 삭제가 두 번 실행되지 않도록, 다이얼로그를 띄우기 전에 잠근다.
    setState(() => _isBulkWorking = true);
    try {
      final confirmed = await showConfirmDialog(
        context,
        title: '선택한 글 삭제',
        content: '선택한 ${_selectedIds.length}개의 글을 삭제하시겠습니까?',
        confirmLabel: '삭제',
        danger: true,
        haptic: true,
      );
      if (!confirmed || !mounted) return;

      final result = await _bulkActions.deleteItems(_selectedIds);
      if (!mounted) return;
      _applyBulkResult(result, '삭제');
    } finally {
      if (mounted) setState(() => _isBulkWorking = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(_selectionMode ? '${_selectedIds.length}개 선택됨' : '내 글'),
        leading: _selectionMode
            ? IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: '선택 취소',
                onPressed: _endSelectionMode,
              )
            : null,
        actions: _selectionMode
            ? const []
            : [
                IconButton(
                  icon: const Icon(
                    Icons.checklist_rounded,
                    color: AppColors.inkMuted,
                  ),
                  tooltip: '여러 개 선택',
                  onPressed: () => setState(() => _selectionMode = true),
                ),
                PopupMenuButton<bool>(
                  tooltip: '정렬',
                  initialValue: _sortOldestFirst,
                  onSelected: (value) => setState(() {
                    _sortOldestFirst = value;
                    _resetPaging();
                  }),
                  icon: const Icon(
                    Icons.sort_rounded,
                    color: AppColors.inkMuted,
                  ),
                  itemBuilder: (context) => const [
                    PopupMenuItem(value: false, child: Text('최신순')),
                    PopupMenuItem(value: true, child: Text('오래된순')),
                  ],
                ),
                const SizedBox(width: 8),
              ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kPagePadding,
              12,
              kPagePadding,
              12,
            ),
            child: AppSegmented(
              labels: const ['전체', '진행중', '거래완료'],
              selectedIndex: _statusFilter,
              onChanged: (index) => setState(() {
                _statusFilter = index;
                _resetPaging();
              }),
            ),
          ),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _query(uid).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return FeedMessage(
                    icon: Icons.error_outline_rounded,
                    title: '내 글을 불러오지 못했어요',
                    text: '네트워크 상태를 확인한 뒤 다시 시도해주세요.',
                    actionLabel: '다시 시도',
                    onAction: () => setState(() {}),
                  );
                }
                if (!snapshot.hasData) {
                  return const ItemListSkeleton();
                }

                final docs = snapshot.data!.docs;
                final items = LostFoundItem.fromDocs(docs);
                final canLoadMore = docs.length == _limit;
                if (items.isEmpty) {
                  // 상태 필터가 걸려 있으면 "글이 하나도 없는 것"과 "이 상태인
                  // 글만 없는 것"을 구분해서 안내한다.
                  if (_statusFilter != 0) {
                    return FeedMessage(
                      icon: Icons.filter_alt_off_outlined,
                      title: '조건에 맞는 글이 없어요',
                      text: '상태 필터를 바꾸면 다른 글을 볼 수 있어요.',
                      actionLabel: '전체 보기',
                      onAction: () => setState(() {
                        _statusFilter = 0;
                        _resetPaging();
                      }),
                    );
                  }
                  return FeedMessage(
                    icon: Icons.receipt_long_outlined,
                    title: '아직 등록한 글이 없어요',
                    text: '잃어버렸거나 주운 물건이 있다면\n첫 게시글을 등록해보세요.',
                    actionLabel: '글 등록하기',
                    onAction: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const RegisterItemScreen(),
                      ),
                    ),
                  );
                }

                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () =>
                      _query(uid).get(const GetOptions(source: Source.server)),
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 32),
                    itemCount: items.length + (canLoadMore ? 1 : 0),
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      if (index == items.length) {
                        return LoadMoreButton(
                          isLoading: false,
                          onPressed: () =>
                              setState(() => _limit += kLoadMoreStep),
                        );
                      }
                      final item = items[index];
                      final id = item.id;
                      final selected = id != null && _selectedIds.contains(id);
                      return ItemCard(
                        item: item,
                        selectionMode: _selectionMode,
                        selected: selected,
                        onLongPress: id == null
                            ? null
                            : () => _enterSelectionMode(id),
                        onTap: () {
                          if (_selectionMode) {
                            if (id != null) _toggleSelected(id);
                          } else {
                            showItemDetailSheet(context, item);
                          }
                        },
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      bottomNavigationBar: _selectionMode && _selectedIds.isNotEmpty
          ? Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kPagePadding,
                    10,
                    kPagePadding,
                    12,
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isBulkWorking ? null : _bulkMarkResolved,
                          icon: _isBulkWorking
                              ? const SizedBox(
                                  width: 16,
                                  height: 16,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: AppColors.primary,
                                  ),
                                )
                              : const Icon(Icons.check_circle_outline),
                          label: const Text('거래완료 처리'),
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: _isBulkWorking ? null : _bulkDelete,
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.danger,
                            side: const BorderSide(color: AppColors.danger),
                          ),
                          icon: const Icon(Icons.delete_outline),
                          label: const Text('삭제'),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            )
          : null,
    );
  }
}
