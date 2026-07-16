import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/lost_found_item.dart';
import '../theme/app_theme.dart';
import '../widgets/feed_message.dart';
import '../widgets/item_card.dart';
import 'item_detail_sheet.dart';

/// 화면: 내가 등록한 글 모아보기
class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({super.key});

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  static const int _pageSize = 20;
  int _loadedPages = 1;

  // 상태 필터: 0 = 전체, 1 = 진행중, 2 = 거래완료
  int _statusFilter = 0;
  // 정렬 기준: false = 최신순, true = 오래된순
  bool _sortOldestFirst = false;

  bool _selectionMode = false;
  final Set<String> _selectedIds = {};

  Query<Map<String, dynamic>> _query(String? uid) => itemsCollection
      .where('authorUid', isEqualTo: uid)
      .orderBy('createdAt', descending: !_sortOldestFirst)
      .limit(_pageSize * _loadedPages);

  List<LostFoundItem> _applyStatusFilter(List<LostFoundItem> items) {
    switch (_statusFilter) {
      case 1:
        return items.where((item) => !item.resolved).toList();
      case 2:
        return items.where((item) => item.resolved).toList();
      default:
        return items;
    }
  }

  void _showDetail(BuildContext context, LostFoundItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => ItemDetailSheet(item: item),
    );
  }

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

  Future<void> _bulkMarkResolved() async {
    if (_selectedIds.isEmpty) return;
    final batch = FirebaseFirestore.instance.batch();
    for (final id in _selectedIds) {
      batch.update(itemsCollection.doc(id), {'resolved': true});
    }
    try {
      await batch.commit();
      if (mounted) _endSelectionMode();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('일괄 처리에 실패했습니다: $e')));
      }
    }
  }

  Future<void> _bulkDelete() async {
    if (_selectedIds.isEmpty) return;
    final count = _selectedIds.length;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('선택한 글 삭제'),
        content: Text('선택한 $count개의 글을 삭제하시겠습니까?'),
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
    final batch = FirebaseFirestore.instance.batch();
    for (final id in _selectedIds) {
      batch.delete(itemsCollection.doc(id));
    }
    try {
      await batch.commit();
      if (mounted) _endSelectionMode();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('삭제에 실패했습니다: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(_selectionMode ? '${_selectedIds.length}개 선택됨' : '내 글'),
        backgroundColor: AppColors.bg,
        elevation: 0,
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
                    _loadedPages = 1;
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
          _buildStatusChips(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _query(uid).snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return const FeedMessage(
                    icon: Icons.error_outline_rounded,
                    text: '내 글을 불러오지 못했습니다.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }

                final docs = snapshot.data!.docs;
                final allItems = docs.map(LostFoundItem.fromDoc).toList();
                final items = _applyStatusFilter(allItems);
                final canLoadMore = docs.length == _pageSize * _loadedPages;
                if (allItems.isEmpty) {
                  return const FeedMessage(
                    icon: Icons.receipt_long_outlined,
                    text: '아직 등록한 글이 없어요.\n첫 게시글을 등록해보세요!',
                  );
                }
                if (items.isEmpty) {
                  return const FeedMessage(
                    icon: Icons.filter_alt_off_outlined,
                    text: '조건에 맞는 글이 없어요.',
                  );
                }

                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () =>
                      _query(uid).get(const GetOptions(source: Source.server)),
                  child: ListView.builder(
                    padding: const EdgeInsets.all(20),
                    itemCount: items.length + (canLoadMore ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == items.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: OutlinedButton(
                              onPressed: () =>
                                  setState(() => _loadedPages += 1),
                              child: const Text('더 보기'),
                            ),
                          ),
                        );
                      }
                      final item = items[index];
                      final id = item.id;
                      final selected = id != null && _selectedIds.contains(id);
                      return Stack(
                        children: [
                          GestureDetector(
                            onLongPress: id == null
                                ? null
                                : () => _enterSelectionMode(id),
                            child: ItemCard(
                              item: item,
                              onTap: () {
                                if (_selectionMode) {
                                  if (id != null) _toggleSelected(id);
                                } else {
                                  _showDetail(context, item);
                                }
                              },
                            ),
                          ),
                          if (_selectionMode)
                            Positioned(
                              top: 22,
                              right: 10,
                              child: IgnorePointer(
                                child: Container(
                                  width: 24,
                                  height: 24,
                                  decoration: BoxDecoration(
                                    shape: BoxShape.circle,
                                    color: selected
                                        ? AppColors.primary
                                        : Colors.white,
                                    border: Border.all(
                                      color: selected
                                          ? AppColors.primary
                                          : AppColors.line,
                                      width: 1.5,
                                    ),
                                  ),
                                  child: selected
                                      ? const Icon(
                                          Icons.check_rounded,
                                          size: 16,
                                          color: Colors.white,
                                        )
                                      : null,
                                ),
                              ),
                            ),
                        ],
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
          ? SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 12),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _bulkMarkResolved,
                        icon: const Icon(Icons.check_circle_outline),
                        label: const Text('거래완료 처리'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _bulkDelete,
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
            )
          : null,
    );
  }

  Widget _buildStatusChips() {
    const labels = ['전체', '진행중', '거래완료'];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: labels.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = _statusFilter == index;
          return GestureDetector(
            onTap: () => setState(() => _statusFilter = index),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.line,
                ),
              ),
              child: Text(
                labels[index],
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.inkMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
