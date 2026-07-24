import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/lost_found_item.dart';

/// 종류·카테고리·장소 필터에서 "필터를 적용하지 않음"을 뜻하는 라벨.
const String kAllFilterLabel = '전체';

/// 목록 화면의 첫 페이지 크기와 "더 보기"로 늘어나는 크기.
/// 처음 20개를 보여주고, 누를 때마다 10개씩 더 불러온다.
const int kInitialPageLimit = 20;
const int kLoadMoreStep = 10;

/// 홈 피드 목록 쿼리를 조립한다.
///
/// 종류·카테고리·장소는 **반드시 Firestore 쿼리에서** 걸러야 한다. 예전에는
/// limit으로 가져온 20개를 클라이언트에서 걸렀는데, 그러면 limit이 "전체 글
/// 상위 20개"를 세는 바람에 필터를 켜면 그중 일부만 남아 목록이 몇 개 안
/// 나왔다. 서버에서 거르면 limit이 "필터를 통과한 글" 기준이 된다.
///
/// [typeFilter]는 0=전체, 1=습득물, 2=분실물. [category]/[location]은
/// [kAllFilterLabel]이면 적용하지 않는다.
Query<Map<String, dynamic>> buildFeedQuery({
  required Query<Map<String, dynamic>> collection,
  required int typeFilter,
  required String category,
  required String location,
  required bool sortByPopular,
  required int limit,
}) {
  var query = collection;
  switch (typeFilter) {
    case 1:
      query = query.where('type', isEqualTo: ItemType.found.name);
    case 2:
      query = query.where('type', isEqualTo: ItemType.lost.name);
  }
  if (category != kAllFilterLabel) {
    query = query.where('category', isEqualTo: category);
  }
  if (location != kAllFilterLabel) {
    query = query.where('location', isEqualTo: location);
  }
  return query
      .orderBy(sortByPopular ? 'viewCount' : 'createdAt', descending: true)
      .limit(limit);
}

/// 카테고리 칩에 붙는 개수를 셀 때 쓰는 쿼리(정렬·limit 없음).
/// 카테고리 자체는 칩마다 따로 붙이므로 여기서는 빼고, 나머지 필터만 건다.
Query<Map<String, dynamic>> buildCategoryCountQuery({
  required Query<Map<String, dynamic>> collection,
  required int typeFilter,
  required String location,
}) {
  var query = collection;
  switch (typeFilter) {
    case 1:
      query = query.where('type', isEqualTo: ItemType.found.name);
    case 2:
      query = query.where('type', isEqualTo: ItemType.lost.name);
  }
  if (location != kAllFilterLabel) {
    query = query.where('location', isEqualTo: location);
  }
  return query;
}

/// 내 글 화면의 목록 쿼리를 조립한다. 상태 필터도 같은 이유로 서버에서 거른다.
/// [statusFilter]는 0=전체, 1=진행중, 2=거래완료.
Query<Map<String, dynamic>> buildMyPostsQuery({
  required Query<Map<String, dynamic>> collection,
  required String? uid,
  required int statusFilter,
  required bool oldestFirst,
  required int limit,
}) {
  var query = collection.where('authorUid', isEqualTo: uid);
  switch (statusFilter) {
    case 1:
      query = query.where('resolved', isEqualTo: false);
    case 2:
      query = query.where('resolved', isEqualTo: true);
  }
  return query.orderBy('createdAt', descending: !oldestFirst).limit(limit);
}
