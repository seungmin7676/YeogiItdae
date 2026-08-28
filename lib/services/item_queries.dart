import 'package:cloud_firestore/cloud_firestore.dart';

import '../models/lost_found_item.dart';

/// 종류·카테고리·장소 필터에서 "필터를 적용하지 않음"을 뜻하는 라벨.
const String kAllFilterLabel = '전체';

/// 목록 화면의 첫 페이지 크기와 "더 보기"로 늘어나는 크기.
/// 처음 20개를 보여주고, 누를 때마다 10개씩 더 불러온다.
const int kInitialPageLimit = 20;
const int kLoadMoreStep = 10;

/// "더 보기" 행을 계속 보여줄지 판단한다.
///
/// 받은 문서 수가 요청한 개수와 같으면 뒤에 더 남아있을 가능성이 있다고 본다.
/// 여기에 더해 **다음 페이지를 불러오는 중에도 계속 보여준다** — limit을 올리면
/// 쿼리가 새로 구독되는데, 새 스냅샷이 도착하기 전까지는 아직 이전 페이지
/// 개수(= 새 limit보다 작다)만 들고 있어서, 그 사이 "더 보기" 행이 사라졌다가
/// 다시 나타나는 깜빡임이 생겼다.
bool shouldShowLoadMore({
  required int loadedCount,
  required int limit,
  required bool isLoadingMore,
}) => isLoadingMore || loadedCount >= limit;

/// 다음 페이지 로딩 표시를 해제해도 되는지 판단한다.
///
/// StreamBuilder는 스트림이 바뀌어 재구독하는 동안에도 직전 스냅샷을 그대로
/// 들고 있다(hasData가 계속 true다). 그래서 "데이터가 있으니 로딩 끝"으로
/// 판단하면 다음 페이지가 도착하기도 전에 스피너가 즉시 꺼져버렸다.
/// 새 스냅샷이 실제로 도착했을 때(ConnectionState.active)만 해제한다.
bool shouldFinishPageLoad({
  required bool isLoadingMore,
  required bool hasLiveSnapshot,
}) => isLoadingMore && hasLiveSnapshot;

/// 홈 피드 목록 쿼리를 조립한다.
///
/// 종류·카테고리·장소는 **반드시 Firestore 쿼리에서** 걸러야 한다. 예전에는
/// limit으로 가져온 20개를 클라이언트에서 걸렀는데, 그러면 limit이 "전체 글
/// 상위 20개"를 세는 바람에 필터를 켜면 그중 일부만 남아 목록이 몇 개 안
/// 나왔다. 서버에서 거르면 limit이 "필터를 통과한 글" 기준이 된다.
///
/// [typeFilter]는 0=전체, 1=습득물, 2=분실물. [category]/[location]은
/// [kAllFilterLabel]이면 적용하지 않는다.
///
/// [searchToken]이 있으면 **검색 모드**로 동작한다 — 검색 토큰만 서버에서
/// 걸러 전체 컬렉션에서 후보를 찾고, 종류·카테고리·장소는 클라이언트에서
/// 적용한다. 배열 필터와 등호 필터를 전부 조합하면 복합 색인이 조합 폭발을
/// 일으키는데(종류×카테고리×장소×정렬), 검색 토큰 자체가 이미 후보를 아주
/// 좁게 만들어 주므로 나머지를 클라이언트에서 걸러도 목록이 비지 않는다.
Query<Map<String, dynamic>> buildFeedQuery({
  required Query<Map<String, dynamic>> collection,
  required int typeFilter,
  required String category,
  required String location,
  required bool sortByPopular,
  required int limit,
  String? searchToken,
}) {
  // Firestore 규칙도 같은 조건을 요구한다. 관리자에게 숨김 처리된 글이
  // 목록 쿼리에 섞여 내려오거나, 규칙 때문에 전체 쿼리가 실패하지 않게 한다.
  var query = collection.where('hidden', isEqualTo: false);
  if (searchToken != null) {
    query = query.where('searchTokens', arrayContains: searchToken);
  } else {
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
  var query = collection.where('hidden', isEqualTo: false);
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
  var query = collection
      .where('hidden', isEqualTo: false)
      .where('authorUid', isEqualTo: uid);
  switch (statusFilter) {
    case 1:
      query = query.where('resolved', isEqualTo: false);
    case 2:
      query = query.where('resolved', isEqualTo: true);
  }
  return query.orderBy('createdAt', descending: !oldestFirst).limit(limit);
}
