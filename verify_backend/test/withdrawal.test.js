const test = require('node:test');
const assert = require('node:assert');

const {
  WITHDRAWAL_COOLDOWN_DAYS,
  emailKey,
  daysLeftUntil,
} = require('../_withdrawal');

// 에뮬레이터 없이 돌릴 수 있는 순수 로직 테스트.
// (Firestore를 쓰는 recordWithdrawal/checkWithdrawalCooldown은 에뮬레이터가
//  필요해 test/api.test.js 쪽 방식으로 별도 확인해야 한다.)

const DAY_MS = 24 * 60 * 60 * 1000;

test('제한 기간은 30일이다', () => {
  assert.strictEqual(WITHDRAWAL_COOLDOWN_DAYS, 30);
});

test('emailKey는 같은 이메일에 항상 같은 값을 준다', () => {
  assert.strictEqual(emailKey('20225216@hallym.ac.kr'), emailKey('20225216@hallym.ac.kr'));
});

test('emailKey는 대소문자와 앞뒤 공백을 무시한다', () => {
  assert.strictEqual(
    emailKey('20225216@hallym.ac.kr'),
    emailKey('  20225216@HALLYM.AC.KR  '),
  );
});

test('emailKey는 다른 이메일을 구분한다', () => {
  assert.notStrictEqual(
    emailKey('20225216@hallym.ac.kr'),
    emailKey('20225217@hallym.ac.kr'),
  );
});

test('emailKey는 평문 이메일을 그대로 남기지 않는다', () => {
  const key = emailKey('20225216@hallym.ac.kr');
  assert.ok(!key.includes('20225216'));
  assert.ok(!key.includes('hallym'));
  assert.strictEqual(key.length, 64); // sha256 hex
});

test('기간이 남아 있으면 남은 일수를 올림해서 돌려준다', () => {
  const now = Date.now();
  // 정확히 3일 남음
  assert.strictEqual(daysLeftUntil(now + 3 * DAY_MS, now), 3);
  // 2일 12시간 남았으면 "3일 뒤"로 안내해야 한다(0일로 보이면 안 된다).
  assert.strictEqual(daysLeftUntil(now + 2.5 * DAY_MS, now), 3);
  // 1시간만 남아도 1일로 센다.
  assert.strictEqual(daysLeftUntil(now + 60 * 60 * 1000, now), 1);
});

test('기간이 지났으면 0이다', () => {
  const now = Date.now();
  assert.strictEqual(daysLeftUntil(now - 1, now), 0);
  assert.strictEqual(daysLeftUntil(now, now), 0);
  assert.strictEqual(daysLeftUntil(now - 100 * DAY_MS, now), 0);
});

test('탈퇴 직후에는 정확히 제한 일수만큼 남는다', () => {
  const now = Date.now();
  const allowedAt = now + WITHDRAWAL_COOLDOWN_DAYS * DAY_MS;
  assert.strictEqual(daysLeftUntil(allowedAt, now), WITHDRAWAL_COOLDOWN_DAYS);
});
