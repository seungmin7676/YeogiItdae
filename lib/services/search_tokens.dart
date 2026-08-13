/// ---------------------------------------------------------------------------
/// 서버 검색용 토큰(2-gram) 규칙
///
/// 예전에는 검색이 "이미 불러온 페이지(20~30개)" 안에서만 동작했다. 핵심
/// 사용자 여정이 "잃어버린 물건 찾기"인데, 100번째 전에 올라온 글을 찾으려면
/// "더 보기"를 열 번 눌러야 했다.
///
/// Firestore는 부분 문자열 검색을 지원하지 않고, 한국어는 공백 단위 토큰만으로
/// 부족하다("가방"으로 "책가방"을 찾을 수 있어야 한다). 그래서 글을 저장할 때
/// 제목·설명을 **두 글자 단위로 잘라** [LostFoundItem.searchTokens] 배열에
/// 넣어두고, 검색할 때 그중 하나를 `arrayContains`로 조회해 후보를 서버에서
/// 좁힌 뒤, 최종 판정(전체 문자열 포함 여부)만 클라이언트에서 한다.
/// 후보를 좁히는 용도이므로 교차 어절 2-gram("검은색 백팩" → "색백") 같은
/// 오탐이 섞여도 최종 판정에서 걸러진다.
///
/// 공백을 없애고 비교하므로 띄어쓰기가 달라도 찾을 수 있다
/// ("아이폰 15" ↔ "아이폰15").
///
/// **이 파일의 규칙은 verify_backend/_search.js와 정확히 같아야 한다.**
/// 기존 글 백필이 앱과 다른 토큰을 만들면 그 글들은 영영 검색되지 않는다.
/// 양쪽 모두 코드 포인트 단위로 순회한다(Dart runes ↔ JS Array.from).
/// ---------------------------------------------------------------------------
library;

/// 토큰을 만들 때 사용할 제목·설명의 최대 길이. 설명이 아주 긴 글에서 문서
/// 크기와 색인 항목이 무한정 늘어나지 않도록 앞부분만 대상으로 한다.
const int kSearchTitleBudget = 60;
const int kSearchDescriptionBudget = 500;

/// 한 문서가 가질 수 있는 토큰 수 상한(안전장치).
const int kMaxSearchTokens = 600;

/// 검색 비교의 기준 형태로 바꾼다 — 소문자 + 모든 공백 제거.
String normalizeForSearch(String input) =>
    input.toLowerCase().replaceAll(RegExp(r'\s+'), '');

/// 글을 저장할 때 넣을 검색 토큰 목록을 만든다.
List<String> buildSearchTokens(String title, String description) {
  final source =
      normalizeForSearch(_take(title, kSearchTitleBudget)) +
      normalizeForSearch(_take(description, kSearchDescriptionBudget));

  final chars = source.runes.map(String.fromCharCode).toList();
  if (chars.isEmpty) return const [];
  // 전체가 한 글자뿐이면 2-gram을 만들 수 없으니 그 글자를 그대로 넣는다.
  if (chars.length == 1) return [chars.first];

  final tokens = <String>{};
  for (var i = 0; i + 1 < chars.length; i++) {
    tokens.add(chars[i] + chars[i + 1]);
    if (tokens.length >= kMaxSearchTokens) break;
  }
  return tokens.toList();
}

/// 검색어로 서버 조회에 쓸 토큰 하나를 고른다.
///
/// 두 글자 미만이면 null을 돌려준다 — 한 글자짜리 검색어는 2-gram으로 만들 수
/// 없고, 거의 모든 글에 걸려 후보를 좁히지도 못한다. 호출한 쪽은 이때
/// 서버 토큰 필터 없이 기존처럼 불러온 목록 안에서만 거른다.
String? searchTokenFor(String query) {
  final chars = normalizeForSearch(
    query,
  ).runes.map(String.fromCharCode).toList();
  if (chars.length < 2) return null;
  return chars[0] + chars[1];
}

/// 서버가 좁혀준 후보 안에서 실제로 검색어를 포함하는지 최종 판정한다.
/// 토큰과 같은 기준(소문자·공백 무시)으로 비교하므로, 띄어쓰기만 다른 글도
/// 정상적으로 걸린다.
bool matchesSearchQuery(
  String query, {
  required String title,
  required String description,
}) {
  final needle = normalizeForSearch(query);
  if (needle.isEmpty) return true;
  final haystack = normalizeForSearch(title) + normalizeForSearch(description);
  return haystack.contains(needle);
}

String _take(String value, int max) =>
    value.length <= max ? value : value.substring(0, max);
