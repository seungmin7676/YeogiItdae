const { initAdmin, setCors, requireUser } = require('../_lib');
const { buildSearchTokens } = require('../_search');

// 운영 데이터 백필이 완료된 일회성 도구다. Vercel Hobby의 Serverless Function
// 12개 제한에 포함되지 않도록 api 밖에 보관하며, 필요하면 로컬 테스트 후
// 임시 관리자 작업으로만 실행한다.

// firestore.rules / lib/services/admin.dart 의 관리자 이메일과 반드시 일치시킨다.
const ADMIN_EMAIL = '20225216@hallym.ac.kr';

// 한 번 호출에서 처리할 문서 수. 서버리스 실행 시간 안에 끝나도록 나눠 돌리고,
// 남은 게 있으면 응답의 done:false 를 보고 다시 호출하면 된다.
const PAGE_SIZE = 300;
const BATCH_CHUNK = 450;

/**
 * 서버 검색·숨김 필터가 도입되기 전에 등록된 글에 필수 필드를 채운다(관리자 전용).
 *
 * 검색은 `searchTokens` 배열을 arrayContains로 조회하므로, 이 필드가 없는
 * 예전 글은 **검색 결과에 아예 나오지 않는다.** 배포 후 한 번은 반드시
 * 돌려야 한다. 이미 토큰이 있는 글은 건드리지 않으므로 여러 번 호출해도
 * 안전하다(멱등).
 *
 * Firestore에는 "필드가 없는 문서만" 조회하는 방법이 없으므로 문서 ID 순으로
 * 전체를 훑는다. 한 번에 다 돌면 실행 시간을 넘길 수 있어, 응답의 nextCursor를
 * 다음 호출에 넘겨 이어서 처리한다. 현재는 운영 백필이 끝나 production API에서
 * 제외됐으며, 다시 필요할 때만 임시 관리자 작업으로 실행한다.
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
    const update = {};
    if (!Array.isArray(data.searchTokens) || data.searchTokens.length === 0) {
      update.searchTokens = buildSearchTokens(data.title || '', data.description || '');
    }
    // 목록 규칙과 모든 앱 쿼리는 hidden == false를 명시한다. 이 필드가 없던
    // 예전 글은 백필하지 않으면 안전하게 거부돼 피드에서 사라져 보인다.
    if (typeof data.hidden !== 'boolean') update.hidden = false;
    if (Object.keys(update).length === 0) continue;
    pending.push({
      ref: doc.ref,
      update,
    });
  }

  for (let i = 0; i < pending.length; i += BATCH_CHUNK) {
    const chunk = pending.slice(i, i + BATCH_CHUNK);
    const batch = db.batch();
    for (const p of chunk) {
      batch.set(p.ref, p.update, { merge: true });
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
