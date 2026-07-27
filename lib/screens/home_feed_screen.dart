import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lost_found_item.dart';
import '../services/item_queries.dart';
import '../services/recent_search_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/app_user_data.dart';
import '../widgets/feed_message.dart';
import '../widgets/hallym_logo.dart';
import '../widgets/item_card.dart';
import '../widgets/searchable_picker_sheet.dart';
import '../widgets/skeleton.dart';
import 'item_detail_sheet.dart';
import 'notifications_screen.dart';
import 'register_item_screen.dart';

const String _kAllLocations = kAllFilterLabel;

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
  // '전체'면 장소 필터를 적용하지 않는다.
  String _selectedLocation = _kAllLocations;
  final TextEditingController _searchController = TextEditingController();
  final _searchFocusNode = FocusNode();
  String _searchQuery = '';
  Timer? _searchDebounce;
  List<String> _recentSearches = [];
  // 정렬 기준: false = 최신순, true = 조회순(인기순)
  bool _sortByPopular = false;

  int _limit = kInitialPageLimit;
  bool _isLoadingMore = false;

  /// 필터·정렬이 바뀌면 이전 필터 기준으로 늘려둔 개수를 그대로 쓰면 안 되므로
  /// 처음 개수로 되돌린다.
  void _resetPaging() => _limit = kInitialPageLimit;

  // 카테고리 칩의 숫자는 전체 목록을 다시 구독해서 세지 않고 count() 집계
  // 쿼리로 서버에서 직접 센다. 실시간은 아니지만(집계 쿼리는 스냅샷 구독을
  // 지원하지 않는다), 필터가 바뀌거나 새로고침할 때 다시 계산한다.
  Future<Map<String, int>> _categoryCountsFuture = Future.value(const {});

  @override
  void initState() {
    super.initState();
    loadRecentSearches().then((searches) {
      if (mounted) setState(() => _recentSearches = searches);
    });
    _searchFocusNode.addListener(() {
      if (!_searchFocusNode.hasFocus) _saveCurrentSearch();
      if (mounted) setState(() {});
    });
    _refreshCategoryCounts();
  }

  void _refreshCategoryCounts() {
    setState(() {
      _categoryCountsFuture = _loadCategoryCounts();
    });
  }

  /// 차단한 작성자·신고 누적으로 숨김 처리된 글도 그대로 세는 근사치다.
  /// 정확히 세려면 문서를 전부 읽어야 하는데, 배지 숫자 하나 때문에 매번
  /// 전체 컬렉션을 읽는 비용이 더 크다고 판단해 정확도보다 비용을 우선했다.
  Future<Map<String, int>> _loadCategoryCounts() async {
    final counts = await Future.wait(
      kItemCategories.map((category) async {
        final snap = await _categoryCountQuery
            .where('category', isEqualTo: category)
            .count()
            .get();
        return MapEntry(category, snap.count ?? 0);
      }),
    );
    return Map.fromEntries(counts);
  }

  @override
  void dispose() {
    _searchDebounce?.cancel();
    _searchController.dispose();
    _searchFocusNode.dispose();
    super.dispose();
  }

  void _onSearchChanged(String value) {
    // 지우기 버튼/최근 검색어 표시는 즉시 갱신하되, 실제 필터링에 쓰이는
    // _searchQuery는 타이핑이 잠시 멈췄을 때만 반영해 매 키 입력마다
    // Firestore 스트림이 새로 구독되는 것을 막는다.
    setState(() {});
    _searchDebounce?.cancel();
    _searchDebounce = Timer(const Duration(milliseconds: 300), () {
      if (mounted) setState(() => _searchQuery = value);
    });
  }

  Future<void> _saveCurrentSearch() async {
    // _searchQuery는 디바운스로 늦게 반영되므로, 방금 입력한 검색어를
    // 그대로 저장하려면 컨트롤러의 현재 텍스트를 직접 읽어야 한다.
    final query = _searchController.text.trim();
    if (query.isEmpty) return;
    await addRecentSearch(query);
    final updated = await loadRecentSearches();
    if (mounted) setState(() => _recentSearches = updated);
  }

  void _applyRecentSearch(String query) {
    // 타이핑 중이던 내용에 대한 디바운스 타이머가 남아있으면, 이 선택을
    // 나중에 덮어쓸 수 있으니 먼저 취소한다.
    _searchDebounce?.cancel();
    _searchController.text = query;
    setState(() => _searchQuery = query);
    _searchFocusNode.unfocus();
  }

  Future<void> _removeRecentSearch(String query) async {
    await removeRecentSearch(query);
    final updated = await loadRecentSearches();
    if (mounted) setState(() => _recentSearches = updated);
  }

  /// 서버 쿼리로 거를 수 없는 조건만 클라이언트에서 마저 거른다.
  /// 종류·카테고리·장소는 Firestore 쿼리에서 이미 걸러져 들어온다
  /// (예전에는 여기서 걸렀는데, limit으로 가져온 20개 안에서만 필터가
  /// 적용돼 필터를 켜면 결과가 몇 개 안 나오는 문제가 있었다).
  /// 숨김 글·차단 사용자·본문 검색은 Firestore가 지원하지 않거나(부분 문자열
  /// 검색) 사용자마다 기준이 달라(차단 목록) 서버로 내릴 수 없다.
  List<LostFoundItem> _applySearch(
    List<LostFoundItem> items,
    Set<String> blockedUids,
  ) {
    final result = items
        .where(
          (item) => !item.isHidden && !blockedUids.contains(item.authorUid),
        )
        .toList();
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

  // 검색 중이라도 항상 페이지네이션 limit을 적용한다. 예전에는 검색어가
  // 있으면 limit을 아예 없애 전체 컬렉션을 매번 구독했는데, 게시글이
  // 늘어날수록 검색할 때마다 읽기 비용이 무한정 커지는 문제가 있었다.
  // 대신 현재 페이지에서 못 찾으면 "더 보기"로 다음 페이지를 불러와
  // 계속 찾을 수 있게 한다.
  Query<Map<String, dynamic>> get _filteredQuery => buildFeedQuery(
    collection: itemsCollection,
    typeFilter: _selectedFilter,
    category: _selectedCategory,
    location: _selectedLocation,
    sortByPopular: _sortByPopular,
    limit: _limit,
  );

  // 카테고리 칩 개수는 페이지네이션과 무관하게 현재 필터(종류·장소) 전체를
  // 대상으로 세야 하므로, 목록용 _filteredQuery와 별도로 limit 없는 쿼리를 둔다.
  Query<Map<String, dynamic>> get _categoryCountQuery =>
      buildCategoryCountQuery(
        collection: itemsCollection,
        typeFilter: _selectedFilter,
        location: _selectedLocation,
      );

  Future<void> _pickLocation() async {
    final result = await showSearchablePickerSheet(
      context: context,
      title: '장소 선택',
      options: kLocations,
      leadingLabel: _kAllLocations,
    );
    if (result != null) {
      setState(() {
        _selectedLocation = result;
        _resetPaging();
      });
      // 장소가 바뀌면 카테고리별 개수도 그 장소 기준으로 다시 세야 한다.
      _refreshCategoryCounts();
    }
  }

  Future<void> _goToRegisterScreen() async {
    await Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterItemScreen()),
    );
    // 새 글 등록으로 카테고리 분포가 바뀌었을 수 있으니 돌아오면 다시 센다.
    if (mounted) _refreshCategoryCounts();
  }

  void _showDetail(LostFoundItem item) {
    incrementItemViewCount(item);
    showItemDetailSheet(context, item);
  }

  void _loadNextPage() {
    setState(() {
      _isLoadingMore = true;
      _limit += kLoadMoreStep;
    });
  }

  @override
  Widget build(BuildContext context) {
    final blockedUids = AppUserData.of(context).blockedUids;
    return Scaffold(
      appBar: AppBar(
        titleSpacing: kPagePadding,
        title: const Row(
          children: [HallymLogo(size: 24), SizedBox(width: 10), Text('여기있대!')],
        ),
        actions: const [NotificationBellButton(), SizedBox(width: 10)],
      ),
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
              focusNode: _searchFocusNode,
              onChanged: _onSearchChanged,
              onSubmitted: (_) => _saveCurrentSearch(),
              decoration: appSearchDecoration(
                '어떤 물건을 찾고 계세요?',
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
          if (_searchFocusNode.hasFocus &&
              _searchController.text.isEmpty &&
              _recentSearches.isNotEmpty)
            SizedBox(
              height: 38,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.fromLTRB(
                  kPagePadding,
                  0,
                  kPagePadding,
                  6,
                ),
                itemCount: _recentSearches.length,
                separatorBuilder: (context, index) => const SizedBox(width: 6),
                itemBuilder: (context, index) {
                  final query = _recentSearches[index];
                  return InputChip(
                    label: Text(query),
                    labelStyle: const TextStyle(
                      fontSize: 12.5,
                      color: AppColors.inkMuted,
                    ),
                    backgroundColor: AppColors.surface,
                    side: const BorderSide(color: AppColors.lineStrong),
                    shape: const StadiumBorder(),
                    deleteIconColor: AppColors.inkFaint,
                    onPressed: () => _applyRecentSearch(query),
                    onDeleted: () => _removeRecentSearch(query),
                  );
                },
              ),
            ),
          Padding(
            padding: const EdgeInsets.fromLTRB(
              kPagePadding,
              2,
              kPagePadding,
              10,
            ),
            child: AppSegmented(
              labels: const ['전체', '습득물', '분실물'],
              selectedIndex: _selectedFilter,
              onChanged: (index) {
                setState(() {
                  _selectedFilter = index;
                  _resetPaging();
                });
                _refreshCategoryCounts();
              },
            ),
          ),
          FutureBuilder<Map<String, int>>(
            future: _categoryCountsFuture,
            builder: (context, countSnapshot) {
              return _buildFilterRow(countSnapshot.data ?? const {});
            },
          ),
          const SizedBox(height: 10),
          const Divider(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _filteredQuery.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return FeedMessage(
                    icon: Icons.error_outline_rounded,
                    title: '목록을 불러오지 못했어요',
                    text: '네트워크 상태를 확인한 뒤 다시 시도해주세요.',
                    actionLabel: '다시 시도',
                    onAction: () => setState(() {}),
                  );
                }
                if (!snapshot.hasData) {
                  return const ItemListSkeleton();
                }

                if (_isLoadingMore) {
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    if (mounted) setState(() => _isLoadingMore = false);
                  });
                }

                final docs = snapshot.data!.docs;
                final visibleItems = LostFoundItem.fromDocs(
                  docs,
                ).where((item) => !item.isHidden).toList();
                final items = _applySearch(visibleItems, blockedUids);
                // 받은 문서 수가 요청한 개수(limit)와 같으면 더 남아있을 가능성이 있다고 본다.
                // 검색 중에도 마찬가지다 — 현재 페이지에는 없어도 더 오래된 페이지에
                // 일치하는 글이 있을 수 있으므로 "더 보기"로 계속 찾을 수 있게 한다.
                final canLoadMore = docs.length == _limit;

                if (items.isEmpty && canLoadMore) {
                  return FeedMessage(
                    icon: Icons.search_off_rounded,
                    title: '아직 찾지 못했어요',
                    text: '지금까지 불러온 글에는 일치하는 결과가 없어요.\n더 불러와서 계속 찾아볼 수 있어요.',
                    actionLabel: _isLoadingMore ? '불러오는 중…' : '더 불러오기',
                    onAction: _isLoadingMore ? () {} : _loadNextPage,
                  );
                }

                if (items.isEmpty) {
                  final isSearching = _searchQuery.trim().isNotEmpty;
                  final hasFilter =
                      _selectedCategory != '전체' ||
                      _selectedLocation != _kAllLocations ||
                      _selectedFilter != 0;
                  if (isSearching) {
                    return const FeedMessage(
                      icon: Icons.search_off_rounded,
                      title: '검색 결과가 없어요',
                      text: '다른 검색어로 다시 찾아보세요.',
                    );
                  }
                  if (hasFilter) {
                    return FeedMessage(
                      icon: Icons.filter_alt_off_outlined,
                      title: '조건에 맞는 글이 없어요',
                      text: '필터를 바꾸거나 해제하면 더 많은 글을 볼 수 있어요.',
                      actionLabel: '필터 모두 해제',
                      onAction: () {
                        setState(() {
                          _selectedFilter = 0;
                          _selectedCategory = '전체';
                          _selectedLocation = _kAllLocations;
                          _resetPaging();
                        });
                        _refreshCategoryCounts();
                      },
                    );
                  }
                  return FeedMessage(
                    icon: Icons.inbox_outlined,
                    title: '아직 등록된 글이 없어요',
                    text: '잃어버렸거나 주운 물건이 있다면\n첫 게시글을 등록해보세요.',
                    actionLabel: '글 등록하기',
                    onAction: _goToRegisterScreen,
                  );
                }

                return RefreshIndicator(
                  color: AppColors.primary,
                  onRefresh: () async {
                    _refreshCategoryCounts();
                    await _filteredQuery.get(
                      const GetOptions(source: Source.server),
                    );
                  },
                  child: ListView.separated(
                    padding: const EdgeInsets.only(bottom: 100),
                    itemCount: items.length + (canLoadMore ? 1 : 0),
                    separatorBuilder: (context, index) => const Divider(),
                    itemBuilder: (context, index) {
                      if (index == items.length) {
                        return LoadMoreButton(
                          isLoading: _isLoadingMore,
                          onPressed: _loadNextPage,
                        );
                      }
                      final item = items[index];
                      return ItemCard(
                        item: item,
                        onTap: () => _showDetail(item),
                      );
                    },
                  ),
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _goToRegisterScreen,
        icon: const Icon(Icons.edit_rounded, size: 18),
        label: const Text(
          '글쓰기',
          style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15),
        ),
      ),
    );
  }

  /// 장소·정렬 트리거 칩과 카테고리 칩을 한 줄에 모은 필터 행.
  /// 흩어져 있던 필터 도구(앱바 아이콘·별도 칩 줄)를 한 자리로 모았다.
  Widget _buildFilterRow(Map<String, int> categoryCounts) {
    final labels = ['전체', ...kItemCategories];
    final totalCount = categoryCounts.values.fold(0, (a, b) => a + b);
    final locationActive = _selectedLocation != _kAllLocations;
    return SizedBox(
      height: 36,
      child: ListView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: kPagePadding),
        children: [
          TriggerChip(
            label: locationActive ? _selectedLocation : '장소',
            icon: Icons.place_outlined,
            active: locationActive,
            onTap: _pickLocation,
            onClear: () {
              setState(() {
                _selectedLocation = _kAllLocations;
                _resetPaging();
              });
              _refreshCategoryCounts();
            },
          ),
          const SizedBox(width: 6),
          SegmentedToggle(
            leftLabel: '최신순',
            rightLabel: '조회순',
            value: _sortByPopular,
            onChanged: (popular) => setState(() {
              _sortByPopular = popular;
              _resetPaging();
            }),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            child: Container(width: 1, color: AppColors.lineStrong),
          ),
          for (var i = 0; i < labels.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Builder(
              builder: (context) {
                final label = labels[i];
                final count = label == '전체'
                    ? totalCount
                    : (categoryCounts[label] ?? 0);
                return SelectChip(
                  label: count > 0 ? '$label $count' : label,
                  selected: _selectedCategory == label,
                  onTap: () => setState(() {
                    _selectedCategory = label;
                    _resetPaging();
                  }),
                );
              },
            ),
          ],
        ],
      ),
    );
  }
}
