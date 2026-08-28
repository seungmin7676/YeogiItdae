const {
  initAdmin,
  setCors,
  requireUser,
  enforceAppCheckIfConfigured,
  enforceRateLimit,
} = require('../_lib');
const {
  WITHDRAWAL_COOLDOWN_DAYS,
  recordWithdrawal,
  deleteUserOwnedData,
} = require('../_withdrawal');

/**
 * 회원 탈퇴를 마무리한다 — 소유 데이터 정리 + 재가입 제한 기록 + Auth 계정 삭제.
 *
 * 계정 삭제를 클라이언트(user.delete())가 아니라 여기서 하는 이유는, 삭제와
 * "탈퇴했다는 기록"이 반드시 함께 남아야 하기 때문이다. 클라이언트가 지우면
 * 기록을 건너뛰고 계정만 지워 제한을 피할 여지가 생긴다.
 *
 * 앱 데이터(items, notifications, userPrivate 등)도 이 요청에서 Admin SDK로
 * 정리한다. 클라이언트가 먼저 지우면 요청 전달 실패 시 계정만 남고 데이터가
 * 유실되므로, 삭제 순서를 서버 경계 안에 모아 재시도 가능하게 유지한다.
 *
 * ⚠️ Firebase 콘솔 > Authentication > Settings 에서 클라이언트 계정 삭제를
 * 꺼두어야, Auth REST API를 직접 호출해 기록 없이 탈퇴하는 우회를 막을 수 있다.
 */
module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  if (!(await enforceAppCheckIfConfigured(req, res, 'withdraw'))) return;
  const decoded = await requireUser(req, res);
  if (!decoded) return;
  if (!(await enforceRateLimit(admin, req, res, {
    scope: 'withdraw-user',
    identifier: decoded.uid,
    max: 5,
    windowMs: 60 * 60 * 1000,
  }))) return;

  const email = decoded.email;
  if (!email) return res.status(400).json({ error: 'no-email' });

  // 기록이 먼저다. 계정을 지운 뒤에 기록에 실패하면 제한이 통째로 사라진다.
  await recordWithdrawal(admin, email);

  // 사용자 데이터 삭제까지 서버가 책임져야 클라이언트와 이 API 사이의 네트워크
  // 실패로 계정은 남고 데이터만 사라지는 순서 역전이 생기지 않는다. 정리는
  // 멱등이므로 중간 실패 뒤 같은 요청을 다시 보내도 안전하다.
  try {
    await deleteUserOwnedData(admin, decoded.uid);
  } catch (e) {
    console.error('[withdraw] 사용자 데이터 정리 실패:', e.message);
    return res.status(500).json({ error: 'cleanup-failed' });
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
