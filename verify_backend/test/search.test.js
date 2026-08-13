const test = require('node:test');
const assert = require('node:assert');

const {
  buildSearchTokens,
  normalizeForSearch,
  MAX_SEARCH_TOKENS,
} = require('../_search');

// 이 파일의 케이스는 test/services/search_tokens_test.dart와 짝이다.
// 두 구현이 같은 토큰을 만들어야 백필된 기존 글도 앱 검색에 걸린다.
// (에뮬레이터가 필요 없는 순수 함수 테스트라 `node --test test/search.test.js`
//  로도 바로 돌릴 수 있다.)

test('제목을 두 글자 단위로 잘라 토큰을 만든다', () => {
  assert.deepStrictEqual(buildSearchTokens('백팩', ''), ['백팩']);
  assert.deepStrictEqual(buildSearchTokens('검은백팩', ''), ['검은', '은백', '백팩']);
});

test('공백을 없애고 이어붙이므로 띄어쓰기가 달라도 같은 토큰이 나온다', () => {
  assert.deepStrictEqual(
    buildSearchTokens('아이폰 15', ''),
    buildSearchTokens('아이폰15', ''),
  );
});

test('대소문자를 구분하지 않는다', () => {
  assert.deepStrictEqual(
    buildSearchTokens('AirPods', ''),
    buildSearchTokens('airpods', ''),
  );
});

test('제목과 설명을 함께 토큰으로 만든다', () => {
  const tokens = buildSearchTokens('지갑', '검은색 가죽');
  assert.ok(tokens.includes('지갑'));
  assert.ok(tokens.includes('가죽'));
});

test('중복 토큰은 한 번만 넣는다', () => {
  const tokens = buildSearchTokens('가방가방', '');
  assert.strictEqual(tokens.length, new Set(tokens).size);
});

test('내용이 없으면 빈 목록이다', () => {
  assert.deepStrictEqual(buildSearchTokens('', ''), []);
  assert.deepStrictEqual(buildSearchTokens('   ', ''), []);
});

test('한 글자뿐이면 그 글자를 토큰으로 넣는다', () => {
  assert.deepStrictEqual(buildSearchTokens('폰', ''), ['폰']);
});

test('아주 긴 설명이 있어도 토큰 수가 상한을 넘지 않는다', () => {
  const tokens = buildSearchTokens('제목', '가나다라마바사'.repeat(500));
  assert.ok(tokens.length <= MAX_SEARCH_TOKENS);
});

test('normalizeForSearch는 소문자로 바꾸고 공백을 모두 없앤다', () => {
  assert.strictEqual(normalizeForSearch('  AirPods  Pro '), 'airpodspro');
  assert.strictEqual(normalizeForSearch('검은색\n백팩'), '검은색백팩');
});

test('Dart 쪽과 같은 토큰을 만든다(고정 기대값)', () => {
  // test/services/search_tokens_test.dart의 동일 케이스와 값을 맞춰둔 것.
  // 한쪽 규칙만 바뀌면 여기서 깨진다.
  assert.deepStrictEqual(buildSearchTokens('검은백팩', ''), ['검은', '은백', '백팩']);
  assert.deepStrictEqual(buildSearchTokens('지갑', '가죽'), ['지갑', '갑가', '가죽']);
});
