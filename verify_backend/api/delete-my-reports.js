const { initAdmin, setCors, requireUser } = require('../_lib');

// reports 컬렉션은 클라이언트가 읽기/쓰기 전부 차단되어 있어(신고 사유 비공개,
// 위변조 방지) 회원 탈퇴 시 본인이 남긴 신고 기록을 클라이언트에서 지울 수 없다.
// Admin SDK로만 접근 가능하므로 이 엔드포인트에서 대신 정리한다.
module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  const decoded = await requireUser(req, res);
  if (!decoded) return;

  const db = admin.firestore();
  const snap = await db
    .collection('reports')
    .where('reporterUid', '==', decoded.uid)
    .get();

  if (!snap.empty) {
    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
  }

  return res.status(200).json({ ok: true, deleted: snap.size });
};
