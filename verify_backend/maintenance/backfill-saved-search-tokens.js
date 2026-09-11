const { initAdmin, setCors, requireUser } = require('../_lib');
const { buildSearchTokens } = require('../_search');
const { isAdminUser } = require('../_admin_access');

// 운영 데이터 백필이 완료된 일회성 도구다. Vercel 배포 함수 수에 포함되지
// 않도록 maintenance에 보관한다.

const PAGE_SIZE = 300;

function keywordTokens(keywords) {
  return [
    ...new Set(
      (Array.isArray(keywords) ? keywords : [])
        .map((keyword) => buildSearchTokens(keyword, '')[0])
        .filter(Boolean),
    ),
  ];
}

/** 기존 키워드 구독 문서에 서버 후보 조회용 2-gram 대표 토큰을 채운다. */
module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  const decoded = await requireUser(req, res);
  if (!decoded) return;
  if (!isAdminUser(decoded)) {
    return res.status(403).json({ error: 'admin-only' });
  }

  const db = admin.firestore();
  const startAfter = req.body && req.body.startAfter;
  let query = db
    .collection('savedSearches')
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(PAGE_SIZE);
  if (startAfter) query = query.startAfter(String(startAfter));
  const snap = await query.get();

  const batch = db.batch();
  let updated = 0;
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    if (Array.isArray(data.keywordTokens)) continue;
    batch.set(doc.ref, { keywordTokens: keywordTokens(data.keywords) }, { merge: true });
    updated += 1;
  }
  if (updated > 0) await batch.commit();

  const done = snap.size < PAGE_SIZE;
  return res.status(200).json({
    ok: true,
    scanned: snap.size,
    updated,
    done,
    nextCursor: done || snap.empty ? null : snap.docs[snap.docs.length - 1].id,
  });
};

module.exports.keywordTokens = keywordTokens;
