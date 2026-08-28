const crypto = require('node:crypto');
const {
  initAdmin,
  setCors,
  requireUser,
  enforceAppCheckIfConfigured,
  enforceRateLimit,
  isVerifiedHallymUser,
} = require('../_lib');
const { sendPushToUser } = require('../_push');
const { buildSearchTokens, normalizeForSearch } = require('../_search');

// 한 번 등록으로 만들 수 있는 알림 수 상한. 인기 카테고리를 아주 많은 사람이
// 구독한 경우에도 한 요청이 무한정 길어지지 않도록 자른다(서버리스 실행
// 시간 제한도 있다).
const MAX_MATCHES = 500;

const QUERY_TOKEN_CHUNK = 30;

function deliveryId(itemId, recipientUid) {
  return crypto
    .createHash('sha256')
    .update(`keyword-match:${itemId}:${recipientUid}`)
    .digest('hex');
}

async function candidateSubscriptions(db, itemTokens, category) {
  const candidates = new Map();
  for (let i = 0; i < itemTokens.length; i += QUERY_TOKEN_CHUNK) {
    const chunk = itemTokens.slice(i, i + QUERY_TOKEN_CHUNK);
    if (chunk.length === 0) continue;
    const snap = await db
      .collection('savedSearches')
      .where('keywordTokens', 'array-contains-any', chunk)
      .limit(MAX_MATCHES)
      .get();
    snap.docs.forEach((doc) => candidates.set(doc.id, doc));
    if (candidates.size >= MAX_MATCHES) break;
  }
  if (category && candidates.size < MAX_MATCHES) {
    const snap = await db
      .collection('savedSearches')
      .where('categories', 'array-contains', category)
      .limit(MAX_MATCHES)
      .get();
    snap.docs.forEach((doc) => candidates.set(doc.id, doc));
  }
  return [...candidates.values()].slice(0, MAX_MATCHES);
}

async function reserveNotification(admin, db, decoded, itemId, title, match) {
  const id = deliveryId(itemId, match.recipientUid);
  const deliveryRef = db.collection('keywordDeliveries').doc(id);
  const notificationRef = db.collection('notifications').doc(id);
  return db.runTransaction(async (tx) => {
    const existing = await tx.get(deliveryRef);
    if (existing.exists) return false;
    tx.create(deliveryRef, {
      itemId,
      recipientUid: match.recipientUid,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 30 * 24 * 60 * 60 * 1000),
    });
    tx.set(notificationRef, {
      recipientUid: match.recipientUid,
      senderUid: decoded.uid,
      type: 'keyword_match',
      matchType: match.matchType,
      keyword: match.keyword,
      itemId,
      itemTitle: title,
      read: false,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
    });
    return true;
  });
}

/**
 * 새 글의 키워드·카테고리 구독자에게 인앱 알림과 푸시를 보낸다.
 *
 * 예전에는 글을 올린 클라이언트가 savedSearches 컬렉션 전체를 직접 읽어
 * 매칭했다. 그 탓에 보안 규칙에서 savedSearches를 모든 로그인 사용자에게
 * 열어둬야 했고(= 남의 저장 키워드가 uid와 함께 전부 노출), 글 하나 등록할
 * 때마다 클라이언트가 읽는 문서 수가 사용자 수만큼 늘어났다. Admin SDK를 가진
 * 이쪽으로 옮기면서 규칙은 본인만 읽도록 잠갔다.
 *
 * 호출자가 실제로 그 글의 작성자인지 서버에서 다시 확인하므로, 남의 글을
 * 빌미로 임의의 알림을 뿌릴 수 없다.
 */
module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  if (!(await enforceAppCheckIfConfigured(req, res, 'notify-matches'))) return;
  const decoded = await requireUser(req, res);
  if (!decoded) return;
  if (!isVerifiedHallymUser(decoded)) {
    return res.status(403).json({ error: 'verified-hallym-user-required' });
  }

  const itemId = req.body && req.body.itemId;
  if (!itemId || typeof itemId !== 'string') {
    return res.status(400).json({ error: 'missing-item' });
  }
  if (!(await enforceRateLimit(admin, req, res, {
    scope: 'notify-matches-user',
    identifier: decoded.uid,
    max: 30,
    windowMs: 10 * 60 * 1000,
  }))) return;

  const db = admin.firestore();
  const itemDoc = await db.collection('items').doc(itemId).get();
  if (!itemDoc.exists) return res.status(404).json({ error: 'item-not-found' });

  const item = itemDoc.data();
  // 본인이 올린 글에 대해서만 구독 알림을 요청할 수 있다.
  if (item.authorUid !== decoded.uid) {
    return res.status(403).json({ error: 'not-author' });
  }
  // 숨김 처리된 글로는 알림을 보내지 않는다.
  if (item.hidden === true) {
    return res.status(200).json({ ok: true, skipped: 'hidden', matched: 0 });
  }

  const title = String(item.title || '');
  const category = String(item.category || '');
  // 검색과 같은 기준(소문자·공백 무시)으로 비교해, 저장 키워드의 띄어쓰기가
  // 글과 달라도 걸리게 한다.
  const haystack =
    normalizeForSearch(title) + normalizeForSearch(item.description || '');

  const itemTokens = Array.isArray(item.searchTokens)
    ? item.searchTokens.filter((value) => typeof value === 'string')
    : buildSearchTokens(title, item.description || '');
  const subscriptionDocs = await candidateSubscriptions(db, itemTokens, category);

  /** @type {{recipientUid: string, matchType: string, keyword: string}[]} */
  const matches = [];
  for (const doc of subscriptionDocs) {
    if (doc.id === decoded.uid) continue;
    if (matches.length >= MAX_MATCHES) break;

    const data = doc.data() || {};
    const keywords = Array.isArray(data.keywords) ? data.keywords : [];
    const categories = Array.isArray(data.categories) ? data.categories : [];

    const matchedKeyword = keywords.find((k) => {
      const needle = normalizeForSearch(k);
      return needle.length > 0 && haystack.includes(needle);
    });
    const matchedCategory = categories.includes(category) ? category : null;
    if (!matchedKeyword && !matchedCategory) continue;

    // 키워드와 카테고리가 둘 다 일치해도 한 사람에게 한 번만 보낸다
    // (키워드를 우선한다 — 더 구체적인 의도이므로).
    matches.push({
      recipientUid: doc.id,
      matchType: matchedKeyword ? 'keyword' : 'category',
      keyword: matchedKeyword || matchedCategory,
    });
  }

  if (matches.length === 0) {
    return res.status(200).json({ ok: true, matched: 0 });
  }

  // itemId+수신자 조합을 서버에서 예약하고 같은 ID의 인앱 알림을 쓴다.
  // 클라이언트 재시도·연타가 와도 한 사람에게 한 번만 남는다.
  const reservedMatches = [];
  for (const match of matches) {
    if (await reserveNotification(admin, db, decoded, itemId, title, match)) {
      reservedMatches.push(match);
    }
  }
  if (reservedMatches.length === 0) {
    return res.status(200).json({ ok: true, matched: 0, skipped: 'duplicate' });
  }

  // 백그라운드 푸시. 한 명이 실패해도 나머지는 계속 보낸다.
  let pushed = 0;
  for (const m of reservedMatches) {
    try {
      const result = await sendPushToUser(admin, {
        recipientUid: m.recipientUid,
        senderUid: decoded.uid,
        type: 'keyword_match',
        title,
        body:
          m.matchType === 'category'
            ? `구독한 카테고리 '${m.keyword}'에 새 글이 등록됐어요`
            : `저장한 키워드 '${m.keyword}'와 일치하는 글이 등록됐어요`,
        data: { itemId, matchType: m.matchType, keyword: m.keyword },
      });
      if (!result.skipped) pushed += 1;
    } catch (e) {
      console.error('[notify-matches] push failed for', m.recipientUid, e.message);
      // 알림 문서는 결정적 ID라 중복되지 않는다. 예약만 풀어 다음 요청에서
      // 푸시를 재시도할 수 있게 한다.
      await db.collection('keywordDeliveries').doc(deliveryId(itemId, m.recipientUid)).delete();
    }
  }

  return res.status(200).json({ ok: true, matched: reservedMatches.length, pushed });
};
