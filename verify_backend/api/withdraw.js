const { initAdmin, setCors, requireUser } = require('../_lib');
const {
  WITHDRAWAL_COOLDOWN_DAYS,
  recordWithdrawal,
  deleteReportsBy,
} = require('../_withdrawal');

/**
 * 회원 탈퇴를 마무리한다 — 재가입 제한 기록 + 신고 기록 정리 + Auth 계정 삭제.
 *
 * 계정 삭제를 클라이언트(user.delete())가 아니라 여기서 하는 이유는, 삭제와
 * "탈퇴했다는 기록"이 반드시 함께 남아야 하기 때문이다. 클라이언트가 지우면
 * 기록을 건너뛰고 계정만 지워 제한을 피할 여지가 생긴다.
 *
 * 앱 데이터(items, notifications, userPrivate 등)는 본인 소유라 보안 규칙으로
 * 클라이언트가 직접 지울 수 있고, 이 호출 직전에 이미 지운 상태로 들어온다.
 * 여기서는 클라이언트가 손댈 수 없는 것(reports)과 계정 자체만 처리한다.
 *
 * ⚠️ Firebase 콘솔 > Authentication > Settings 에서 클라이언트 계정 삭제를
 * 꺼두어야, Auth REST API를 직접 호출해 기록 없이 탈퇴하는 우회를 막을 수 있다.
 */
module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  const decoded = await requireUser(req, res);
  if (!decoded) return;

  const email = decoded.email;
  if (!email) return res.status(400).json({ error: 'no-email' });

  // 기록이 먼저다. 계정을 지운 뒤에 기록에 실패하면 제한이 통째로 사라진다.
  await recordWithdrawal(admin, email);

  // 신고 기록 정리는 실패해도 탈퇴 자체를 막지 않는다.
  try {
    await deleteReportsBy(admin, decoded.uid);
  } catch (e) {
    console.error('[withdraw] reports 정리 실패:', e.message);
  }

  try {
    await admin.auth().deleteUser(decoded.uid);
  } catch (e) {
    // 이미 지워진 계정이면 성공으로 본다(중복 호출·재시도 대비).
    if (e.code !== 'auth/user-not-found') {
      console.error('[withdraw] 계정 삭제 실패:', e.code, e.message);
      return res.status(500).json({ error: 'delete-failed' });
    }
  }

  return res.status(200).json({ ok: true, cooldownDays: WITHDRAWAL_COOLDOWN_DAYS });
};
