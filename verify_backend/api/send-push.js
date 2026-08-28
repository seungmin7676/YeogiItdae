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

// firestore.rules / lib/services/admin.dart 의 관리자 이메일과 반드시 일치시킨다.
const ADMIN_EMAIL = '20225216@hallym.ac.kr';

const CHAT_TYPES = new Set(['chat_started', 'chat_message']);
const ADMIN_INBOX_TYPES = new Set(['report_received', 'bug_report']);
const MODERATION_TYPES = new Set(['report_result', 'item_hidden', 'item_removed']);
const CHAT_EVENT_MAX_AGE_MS = 5 * 60 * 1000;

function nonEmptyString(value) {
  return typeof value === 'string' && value.trim() ? value.trim() : null;
}

function firestoreDocumentId(value) {
  const id = nonEmptyString(value);
  return id && !id.includes('/') && id.length <= 1500 ? id : null;
}

function deliveryId(sourceKey) {
  return crypto.createHash('sha256').update(sourceKey).digest('hex');
}

async function reserveDelivery(admin, db, sourceKey, senderUid, recipientUid, type) {
  const ref = db.collection('pushDeliveries').doc(deliveryId(sourceKey));
  return db.runTransaction(async (transaction) => {
    const existing = await transaction.get(ref);
    if (existing.exists) return false;
    transaction.create(ref, {
      sourceKey,
      senderUid,
      recipientUid,
      type,
      createdAt: admin.firestore.FieldValue.serverTimestamp(),
      expiresAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + 30 * 24 * 60 * 60 * 1000,
      ),
    });
    return true;
  });
}

async function latestOwnBugReport(db, uid) {
  const snapshot = await db.collection('bugReports').where('reporterUid', '==', uid).get();
  let latest = null;
  for (const doc of snapshot.docs) {
    const millis = doc.data().createdAt?.toMillis?.() ?? 0;
    if (!latest || millis > latest.millis) latest = { doc, millis };
  }
  return latest?.doc ?? null;
}

async function authorizeChatPush(db, decoded, requestBody, type) {
  const recipientUid = nonEmptyString(requestBody.recipientUid);
  const chatId = firestoreDocumentId(requestBody.data?.chatId);
  const messageId = firestoreDocumentId(requestBody.data?.messageId);
  if (!recipientUid || !chatId || recipientUid === decoded.uid) return null;

  const chatDoc = await db.collection('chats').doc(chatId).get();
  if (!chatDoc.exists) return null;
  const chat = chatDoc.data() || {};
  const participants = Array.isArray(chat.participants) ? chat.participants : [];
  if (!participants.includes(decoded.uid) || !participants.includes(recipientUid)) return null;

  // "현재 최신 메시지"를 검사하면 저장 직후 상대의 답장이 먼저 도착했을 때
  // 정상 이벤트가 거부된다. 클라이언트가 방금 저장한 정확한 문서를 검증한다.
  let messageDoc;
  if (messageId) {
    messageDoc = await chatDoc.ref.collection('messages').doc(messageId).get();
  } else {
    // 기존 앱은 messageId를 보내지 않는다. 백엔드 선배포 시 푸시가 전부
    // 끊기지 않도록 최신 메시지 검증을 호환 경로로만 남긴다. 새 앱 요청은
    // 위의 정확한 문서 경로를 사용하므로 빠른 답장 경쟁 상태가 없다.
    const latest = await chatDoc.ref
      .collection('messages')
      .orderBy('createdAt', 'desc')
      .limit(1)
      .get();
    if (latest.empty) return null;
    messageDoc = latest.docs[0];
  }
  if (!messageDoc.exists) return null;
  const message = messageDoc.data() || {};
  if (message.senderUid !== decoded.uid) return null;

  const createdAtMs = message.createdAt?.toMillis?.() ?? 0;
  const ageMs = Date.now() - createdAtMs;
  if (createdAtMs <= 0 || ageMs < -60 * 1000 || ageMs > CHAT_EVENT_MAX_AGE_MS) {
    return null;
  }

  const nicknames = chat.participantNicknames || {};
  let body;
  if (message.type === 'text') {
    body = nonEmptyString(message.text);
  } else if (message.type === 'image' && nonEmptyString(message.imageUrl)) {
    body = '사진을 보냈습니다';
  }
  if (!body) return null;

  return {
    recipientUid,
    type,
    title: nonEmptyString(nicknames[decoded.uid]) || decoded.name || '익명',
    body,
    data: { chatId },
    // 채팅 시작은 방마다 한 번, 일반 메시지는 검증한 메시지 문서마다 한 번이다.
    sourceKey:
      type === 'chat_started'
        ? `chat-started:${chatId}`
        : `chat-message:${chatId}:${messageDoc.id}`,
  };
}

async function authorizeAdminInboxPush(admin, db, decoded, requestBody, type) {
  let sourceKey;
  let title;
  let body;
  let data = {};

  if (type === 'report_received') {
    const itemId = nonEmptyString(requestBody.data?.itemId);
    if (!itemId) return null;
    const reportDoc = await db.collection('reports').doc(`${itemId}_${decoded.uid}`).get();
    if (!reportDoc.exists || reportDoc.data().reporterUid !== decoded.uid) return null;
    const report = reportDoc.data();
    title = '새 신고 접수';
    body = `'${nonEmptyString(report.itemTitle) || '제목 없음'}' 게시글이 신고됐어요`;
    data = { itemId };
    sourceKey = `report-received:${reportDoc.id}`;
  } else {
    const bugReport = await latestOwnBugReport(db, decoded.uid);
    if (!bugReport) return null;
    title = '새 버그 신고';
    body = nonEmptyString(bugReport.data().content) || '새 버그 신고가 접수됐어요';
    sourceKey = `bug-report:${bugReport.id}`;
  }

  let recipientUid;
  try {
    recipientUid = (await admin.auth().getUserByEmail(ADMIN_EMAIL)).uid;
  } catch (_) {
    return { skipped: 'no-admin-account' };
  }
  return { recipientUid, type, title, body, data, sourceKey };
}

function authorizeModerationPush(decoded, requestBody, type) {
  if (decoded.email !== ADMIN_EMAIL || decoded.email_verified !== true) return null;
  const recipientUid = nonEmptyString(requestBody.recipientUid);
  const itemId = nonEmptyString(requestBody.data?.itemId);
  if (!recipientUid || !itemId) return null;
  return {
    recipientUid,
    type,
    title: nonEmptyString(requestBody.title) || '신고 처리 안내',
    body: nonEmptyString(requestBody.body) || '신고 검토가 완료됐어요',
    data: { itemId },
    // 관리자 조치는 Firestore batch 자체가 중복 실행을 막는다. 동일 게시글이
    // 나중에 다시 신고될 수 있으므로 여기서는 영구 중복 키를 만들지 않는다.
    sourceKey: null,
  };
}

// 클라이언트가 이벤트 직후 호출하더라도, 서버가 원본 Firestore 문서와 발신자·
// 수신자 관계를 다시 검증한다. 클라이언트가 보낸 제목/본문/data는 신뢰하지
// 않고 검증된 원본으로 재구성해 시스템 알림 사칭과 임의 화면 이동을 막는다.
module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  if (!(await enforceAppCheckIfConfigured(req, res, 'send-push'))) return;
  const decoded = await requireUser(req, res);
  if (!decoded) return;
  if (!isVerifiedHallymUser(decoded)) {
    return res.status(403).json({ error: 'verified-hallym-user-required' });
  }
  if (!(await enforceRateLimit(admin, req, res, {
    scope: 'send-push-user',
    identifier: decoded.uid,
    max: 120,
    windowMs: 10 * 60 * 1000,
  }))) return;

  const requestBody = req.body || {};
  const type = nonEmptyString(requestBody.type);
  if (!type) return res.status(400).json({ error: 'missing-type' });

  const db = admin.firestore();
  let authorized;
  if (CHAT_TYPES.has(type)) {
    authorized = await authorizeChatPush(db, decoded, requestBody, type);
  } else if (ADMIN_INBOX_TYPES.has(type)) {
    authorized = await authorizeAdminInboxPush(admin, db, decoded, requestBody, type);
  } else if (MODERATION_TYPES.has(type)) {
    authorized = authorizeModerationPush(decoded, requestBody, type);
  } else {
    return res.status(400).json({ error: 'unsupported-type' });
  }

  if (!authorized) return res.status(403).json({ error: 'event-not-authorized' });
  if (authorized.skipped) {
    return res.status(200).json({ ok: true, skipped: authorized.skipped });
  }

  let reserved = false;
  if (authorized.sourceKey) {
    reserved = await reserveDelivery(
      admin,
      db,
      authorized.sourceKey,
      decoded.uid,
      authorized.recipientUid,
      type,
    );
    if (!reserved) return res.status(200).json({ ok: true, skipped: 'duplicate' });
  }

  try {
    const result = await sendPushToUser(admin, {
      recipientUid: authorized.recipientUid,
      senderUid: decoded.uid,
      type,
      title: authorized.title,
      body: authorized.body,
      data: authorized.data,
    });

    if (result.skipped) return res.status(200).json({ ok: true, skipped: result.skipped });
    return res.status(200).json({ ok: true, sent: result.sent, failed: result.failed });
  } catch (error) {
    // 발송 자체가 실패한 경우에는 예약을 풀어 네트워크 복구 후 재시도할 수 있게 한다.
    if (reserved) {
      await db.collection('pushDeliveries').doc(deliveryId(authorized.sourceKey)).delete();
    }
    throw error;
  }
};
