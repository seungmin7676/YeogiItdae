import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/lost_found_item.dart';
import 'search_tokens.dart';

/// 색인이 없는 예전 글·한 글자 검색·설명 뒷부분도 같은 기준으로 찾는다.
/// 문서 ID를 포함한 Firestore 커서로 이어 읽고, 필요한 결과가 모이면 멈춘다.
class FeedSearchPager {
  FeedSearchPager({
    required this.query,
    required this.search,
    this.pageSize = 20,
    this.scanSize = 100,
  });

  final Query<Map<String, dynamic>> query;
  final String search;
  final int pageSize;
  final int scanSize;
  final List<LostFoundItem> _matches = [];
  DocumentSnapshot<Map<String, dynamic>>? _cursor;
  bool _exhausted = false;
  bool _cancelled = false;
  int _shown = 0;
  Future<List<LostFoundItem>>? _loading;

  bool get hasMore => !_exhausted || _matches.length > _shown;
  void cancel() => _cancelled = true;

  Future<List<LostFoundItem>> loadNext() =>
      _loading ??= _load().whenComplete(() => _loading = null);

  Future<List<LostFoundItem>> _load() async {
    final target = _shown + pageSize;
    while (!_cancelled && !_exhausted && _matches.length < target) {
      var next = query;
      if (_cursor != null) next = next.startAfterDocument(_cursor!);
      final snapshot = await next
          .limit(scanSize)
          .get()
          .timeout(const Duration(seconds: 15));
      for (final item in LostFoundItem.fromDocs(snapshot.docs)) {
        if (matchesSearchQuery(
          search,
          title: item.title,
          description: item.description,
        )) {
          _matches.add(item);
        }
      }
      if (snapshot.docs.isNotEmpty) _cursor = snapshot.docs.last;
      _exhausted = snapshot.docs.length < scanSize;
    }
    _shown = target < _matches.length ? target : _matches.length;
    return List.unmodifiable(_matches.take(_shown));
  }
}
