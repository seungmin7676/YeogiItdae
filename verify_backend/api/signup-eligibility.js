const {
  initAdmin,
  setCors,
  enforceAppCheckIfConfigured,
  enforceRateLimit,
  ALLOWED_EMAIL_DOMAIN,
} = require('../_lib');
const { checkWithdrawalCooldown } = require('../_withdrawal');

/**
 * 가입 화면에서 계정을 만들기 **전에** 재가입 제한에 걸리는지 미리 확인한다.
 *
 * 실제 차단은 send-code(이메일 인증 관문)가 하고, 이 엔드포인트는 순전히
 * 사용자 경험용이다 — 미리 확인하지 않으면 계정을 만든 다음에야 거절당해
 * 되돌리는 과정이 필요해진다.
 *
 * 로그인 전이라 ID 토큰이 없으므로, 비밀번호 재설정과 같은 방식으로 App Check로
 * "진짜 이 앱에서 온 요청인지"만 확인한다. 임의의 학번을 넣어 탈퇴 여부를
 * 캐내는 조회를 막기 위한 것이다.
 */
module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  if (!(await enforceAppCheckIfConfigured(req, res, 'signup-eligibility'))) return;

  const email = String((req.body && req.body.email) || '').trim();
  if (!email || !email.toLowerCase().endsWith(ALLOWED_EMAIL_DOMAIN)) {
    return res.status(403).json({ error: 'domain-not-allowed' });
  }

  if (
    !(await enforceRateLimit(admin, req, res, {
      scope: 'signup-eligibility-ip',
      max: 20,
      windowMs: 15 * 60 * 1000,
    })) ||
    !(await enforceRateLimit(admin, req, res, {
      scope: 'signup-eligibility-email',
      identifier: email,
      max: 6,
      windowMs: 60 * 60 * 1000,
    }))
  ) return;

  const { blocked, daysLeft } = await checkWithdrawalCooldown(admin, email);
  return res.status(200).json({ ok: true, allowed: !blocked, daysLeft });
};
