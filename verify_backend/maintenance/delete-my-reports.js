const {
  initAdmin,
  setCors,
  requireUser,
  enforceAppCheckIfConfigured,
} = require('../_lib');
const { deleteReportsBy } = require('../_withdrawal');

// 회원 탈퇴의 /api/withdraw가 동일한 정리를 원자적으로 수행하며 앱에서도 이
// 구형 독립 엔드포인트를 호출하지 않는다. 회귀 테스트용 구현만 보관하고 Vercel
// production 함수에서는 제외한다.

// reports 컬렉션은 클라이언트가 읽기/쓰기 전부 차단되어 있어(신고 사유 비공개,
// 위변조 방지) 본인이 남긴 신고 기록을 클라이언트에서 지울 수 없다.
// Admin SDK로만 접근 가능하므로 이 엔드포인트에서 대신 정리한다.
//
// 회원 탈퇴 흐름은 이제 /api/withdraw가 이 정리까지 함께 처리한다. 이 엔드포인트는
// 신고 기록만 따로 지우고 싶을 때를 위해 남겨둔다(같은 헬퍼를 쓴다).
module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  if (!(await enforceAppCheckIfConfigured(req, res, 'delete-my-reports'))) return;
  const decoded = await requireUser(req, res);
  if (!decoded) return;

  const deleted = await deleteReportsBy(admin, decoded.uid);
  return res.status(200).json({ ok: true, deleted });
};
