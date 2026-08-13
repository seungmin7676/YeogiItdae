const { initAdmin, setCors, requireUser } = require('../_lib');
const { buildSearchTokens } = require('../_search');

// firestore.rules / lib/services/admin.dart 의 관리자 이메일과 반드시 일치시킨다.
const ADMIN_EMAIL = '20225216@hallym.ac.kr';

// 한 번 호출에서 처리할 문서 수. 서버리스 실행 시간 안에 끝나도록 나눠 돌리고,
// 남은 게 있으면 응답의 done:false 를 보고 다시 호출하면 된다.
const PAGE_SIZE = 300;
const BATCH_CHUNK = 450;

/**
 * 서버 검색이 도입되기 전에 등록된 글에 searchTokens를 채워 넣는다(관리자 전용).
 *
 * 검색은 `searchTokens` 배열을 arrayContains로 조회하므로, 이 필드가 없는
 * 예전 글은 **검색 결과에 아예 나오지 않는다.** 배포 후 한 번은 반드시
 * 돌려야 한다. 이미 토큰이 있는 글은 건드리지 않으므로 여러 번 호출해도
 * 안전하다(멱등).
 *
 * Firestore에는 "필드가 없는 문서만" 조회하는 방법이 없으므로 문서 ID 순으로
 * 전체를 훑는다. 한 번에 다 돌면 서버리스 실행 시간을 넘길 수 있어, 응답의
 * nextCursor를 다음 호출에 넘겨 이어서 처리한다:
 *
 *   curl -X POST https://<배포주소>/api/backfill-search-tokens \
 *        -H "Authorization: Bearer <관리자 ID 토큰>" \
 *        -H "Content-Type: application/json" -d '{}'
 *   # 응답 예: { done:false, nextCursor:"abc123", updated: 300 }
 *   curl ... -d '{"startAfter":"abc123"}'
 *
 * done이 true가 될 때까지 반복한다.
 */
module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  const decoded = await requireUser(req, res);
  if (!decoded) return;
  if (decoded.email !== ADMIN_EMAIL || decoded.email_verified !== true) {
    return res.status(403).json({ error: 'admin-only' });
  }

  const db = admin.firestore();
  const startAfter = req.body && req.body.startAfter;

  let query = db
    .collection('items')
    .orderBy(admin.firestore.FieldPath.documentId())
    .limit(PAGE_SIZE);
  if (startAfter) query = query.startAfter(String(startAfter));
  const snap = await query.get();

  const pending = [];
  for (const doc of snap.docs) {
    const data = doc.data() || {};
    // 이미 채워진 글은 건너뛴다 — 여러 번 돌려도 안전하도록.
    if (Array.isArray(data.searchTokens) && data.searchTokens.length > 0) continue;
    pending.push({
      ref: doc.ref,
      tokens: buildSearchTokens(data.title || '', data.description || ''),
    });
  }

  for (let i = 0; i < pending.length; i += BATCH_CHUNK) {
    const chunk = pending.slice(i, i + BATCH_CHUNK);
    const batch = db.batch();
    for (const p of chunk) {
      batch.set(p.ref, { searchTokens: p.tokens }, { merge: true });
    }
    await batch.commit();
  }

  // 받아온 문서가 페이지 크기보다 적으면 컬렉션 끝까지 훑은 것이다.
  const done = snap.size < PAGE_SIZE;
  return res.status(200).json({
    ok: true,
    scanned: snap.size,
    updated: pending.length,
    done,
    nextCursor: done || snap.empty ? null : snap.docs[snap.docs.length - 1].id,
  });
};
