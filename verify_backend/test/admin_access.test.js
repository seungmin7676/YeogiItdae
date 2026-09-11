const test = require('node:test');
const assert = require('node:assert/strict');

const { ADMIN_EMAILS, isAdminEmail, isAdminUser } = require('../_admin_access');

test('전시 관리자 다섯 계정만 관리자 목록에 포함된다', () => {
  assert.equal(ADMIN_EMAILS.size, 5);
  for (let index = 1; index <= 5; index += 1) {
    assert.equal(isAdminEmail(`admin${index}@hallym.ac.kr`), true);
  }
  assert.equal(isAdminEmail('admin6@hallym.ac.kr'), false);
  assert.equal(isAdminEmail('student@hallym.ac.kr'), false);
});

test('관리자는 이메일 인증까지 완료되어야 한다', () => {
  assert.equal(
    isAdminUser({ email: 'ADMIN1@HALLYM.AC.KR', email_verified: true }),
    true,
  );
  assert.equal(
    isAdminUser({ email: 'admin1@hallym.ac.kr', email_verified: false }),
    false,
  );
});
