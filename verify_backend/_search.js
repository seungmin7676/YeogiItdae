// ---------------------------------------------------------------------------
// 검색 토큰(2-gram) 규칙 — lib/services/search_tokens.dart의 이식본.
//
// **두 구현은 정확히 같은 토큰을 만들어야 한다.** 앱이 새 글을 쓸 때 만드는
// 토큰과 백필이 기존 글에 채워 넣는 토큰이 다르면, 백필된 글은 영영 검색되지
// 않는다. 한쪽을 고치면 반드시 다른 쪽도 같이 고치고, 양쪽 테스트
// (test/search.test.js, test/services/search_tokens_test.dart)를 함께 돌린다.
//
// 코드 포인트 단위로 순회하는 것도 맞춰야 한다(Dart runes ↔ JS Array.from).
// ---------------------------------------------------------------------------

const SEARCH_TITLE_BUDGET = 60;
const SEARCH_DESCRIPTION_BUDGET = 500;
const MAX_SEARCH_TOKENS = 600;

/** 검색 비교의 기준 형태로 바꾼다 — 소문자 + 모든 공백 제거. */
function normalizeForSearch(input) {
  return String(input || '').toLowerCase().replace(/\s+/g, '');
}

function take(value, max) {
  const str = String(value || '');
  return str.length <= max ? str : str.slice(0, max);
}

/** 글에 저장할 검색 토큰 목록을 만든다. */
function buildSearchTokens(title, description) {
  const source =
    normalizeForSearch(take(title, SEARCH_TITLE_BUDGET)) +
    normalizeForSearch(take(description, SEARCH_DESCRIPTION_BUDGET));

  const chars = Array.from(source);
  if (chars.length === 0) return [];
  // 전체가 한 글자뿐이면 2-gram을 만들 수 없으니 그 글자를 그대로 넣는다.
  if (chars.length === 1) return [chars[0]];

  const tokens = new Set();
  for (let i = 0; i + 1 < chars.length; i++) {
    tokens.add(chars[i] + chars[i + 1]);
    if (tokens.size >= MAX_SEARCH_TOKENS) break;
  }
  return Array.from(tokens);
}

module.exports = {
  buildSearchTokens,
  normalizeForSearch,
  SEARCH_TITLE_BUDGET,
  SEARCH_DESCRIPTION_BUDGET,
  MAX_SEARCH_TOKENS,
};
