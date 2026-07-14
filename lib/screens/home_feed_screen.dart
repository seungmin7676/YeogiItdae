import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lost_found_item.dart';
import '../theme/app_theme.dart';
import '../widgets/feed_message.dart';
import '../widgets/hallym_logo.dart';
import '../widgets/item_card.dart';
import 'item_detail_sheet.dart';
import 'notifications_screen.dart';
import 'register_item_screen.dart';

class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  // 필터 상태: 0 = 전체, 1 = 습득물, 2 = 분실물
  int _selectedFilter = 0;
  // '전체'면 카테고리 필터를 적용하지 않는다.
  String _selectedCategory = '전체';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  // 정렬 기준: false = 최신순, true = 조회순(인기순)
  bool _sortByPopular = false;

  static const int _pageSize = 20;
  int _loadedPages = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<LostFoundItem> _applySearch(List<LostFoundItem> items) {
    var result = items.where((item) => !item.isHidden).toList();
    if (_selectedCategory != '전체') {
      result = result
          .where((item) => item.category == _selectedCategory)
          .toList();
    }
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return result;
    return result
        .where(
          (item) =>
              item.title.toLowerCase().contains(query) ||
              item.description.toLowerCase().contains(query),
        )
        .toList();
  }

  Query<Map<String, dynamic>> get _filteredQuery {
    Query<Map<String, dynamic>> query;
    switch (_selectedFilter) {
      case 1:
        query = itemsCollection.where('type', isEqualTo: ItemType.found.name);
      case 2:
        query = itemsCollection.where('type', isEqualTo: ItemType.lost.name);
      default:
        query = itemsCollection;
    }
    query = query.orderBy(
      _sortByPopular ? 'viewCount' : 'createdAt',
      descending: true,
    );
    // 검색 중에는 아직 페이지에 로드되지 않은 과거 게시글도 찾을 수 있어야
    // 하므로, 검색어가 있을 때는 페이지네이션 limit을 적용하지 않는다.
    if (_searchQuery.trim().isEmpty) {
      query = query.limit(_pageSize * _loadedPages);
    }
    return query;
  }

  // 카테고리 칩 개수는 페이지네이션과 무관하게 선택된 종류(전체/습득물/분실물)
  // 전체를 대상으로 세야 하므로, 목록용 _filteredQuery와 별도로 limit 없는
  // 쿼리를 둔다.
  Query<Map<String, dynamic>> get _categoryCountQuery {
    switch (_selectedFilter) {
      case 1:
        return itemsCollection.where('type', isEqualTo: ItemType.found.name);
      case 2:
        return itemsCollection.where('type', isEqualTo: ItemType.lost.name);
      default:
        return itemsCollection;
    }
  }

  void _goToRegisterScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterItemScreen()),
    );
  }

  void _showDetail(LostFoundItem item) {
    incrementItemViewCount(item);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            const HallymLogo(size: 26),
            const SizedBox(width: 10),
            const Text('여기있대!'),
          ],
        ),
        actions: [
          PopupMenuButton<bool>(
            tooltip: '정렬',
            initialValue: _sortByPopular,
            onSelected: (value) => setState(() {
              _sortByPopular = value;
              _loadedPages = 1;
            }),
            icon: Icon(
              _sortByPopular ? Icons.trending_up_rounded : Icons.sort_rounded,
              color: AppColors.inkMuted,
            ),
            itemBuilder: (context) => const [
              PopupMenuItem(value: false, child: Text('최신순')),
              PopupMenuItem(value: true, child: Text('조회순')),
            ],
          ),
          const NotificationBellButton(),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: '제목이나 설명으로 검색',
                hintStyle: const TextStyle(color: Color(0xFFB4B7C4)),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.inkMuted,
                ),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.inkMuted,
                        ),
                        onPressed: () {
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
          _buildFilterChips(),
          StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
            stream: _categoryCountQuery.snapshots(),
            builder: (context, countSnapshot) {
              final categoryCounts = <String, int>{};
              for (final doc in countSnapshot.data?.docs ?? const []) {
                final item = LostFoundItem.fromDoc(doc);
                if (item.isHidden) continue;
                categoryCounts[item.category] =
                    (categoryCounts[item.category] ?? 0) + 1;
              }
              return _buildCategoryChips(categoryCounts);
            },
          ),
          const SizedBox(height: 4),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _filteredQuery.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return FeedMessage(
                    icon: Icons.error_outline_rounded,
                    text: '데이터를 불러오지 못했습니다.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }

                final docs = snapshot.data!.docs;
                final visibleItems = docs
                    .map(LostFoundItem.fromDoc)
                    .where((item) => !item.isHidden)
                    .toList();
                final items = _applySearch(visibleItems);
                // 검색 중에는 limit 없이 전체를 이미 불러온 상태이므로 더보기가 필요 없다.
                // 그 외에는 받은 문서 수가 요청한 개수(limit)와 같으면 더 남아있을 가능성이 있다고 본다.
                final canLoadMore =
                    _searchQuery.trim().isEmpty &&
                    docs.length == _pageSize * _loadedPages;

                return items.isEmpty
                    ? FeedMessage(
                        icon: _searchQuery.isEmpty
                            ? Icons.inbox_outlined
                            : Icons.search_off_rounded,
                        text: _searchQuery.isEmpty
                            ? '아직 등록된 게시글이 없어요.\n첫 게시글을 등록해보세요!'
                            : '검색 결과가 없습니다.',
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.fromLTRB(20, 8, 20, 100),
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
                          return ItemCard(
                            item: item,
                            onTap: () => _showDetail(item),
                          );
                        },
                      );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _goToRegisterScreen,
        icon: const Icon(Icons.edit_outlined),
        label: const Text(
          '등록하기',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildFilterChips() {
    const labels = ['전체', '습득물', '분실물'];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: labels.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = _selectedFilter == index;
          return GestureDetector(
            onTap: () => setState(() {
              _selectedFilter = index;
              _loadedPages = 1;
            }),
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

  Widget _buildCategoryChips(Map<String, int> categoryCounts) {
    final labels = ['전체', ...kItemCategories];
    final totalCount = categoryCounts.values.fold(0, (a, b) => a + b);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        itemCount: labels.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final label = labels[index];
          final selected = _selectedCategory == label;
          final count = label == '전체'
              ? totalCount
              : (categoryCounts[label] ?? 0);
          return GestureDetector(
            onTap: () => setState(() {
              _selectedCategory = label;
              _loadedPages = 1;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.line,
                ),
              ),
              child: Text(
                count > 0 ? '$label ($count)' : label,
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.inkMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
