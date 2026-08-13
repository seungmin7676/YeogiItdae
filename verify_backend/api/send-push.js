const { initAdmin, setCors, requireUser } = require('../_lib');
const { sendPushToUser } = require('../_push');

// firestore.rules / lib/services/admin.dart 의 관리자 이메일과 반드시 일치시킨다.
const ADMIN_EMAIL = '20225216@hallym.ac.kr';

// 관리자에게 보내는 알림 종류. recipientUid 없이 서버가 관리자로 라우팅한다.
const ADMIN_TYPES = new Set(['report_received', 'bug_report']);

// 클라이언트가 이벤트를 일으킨 직후 이 엔드포인트를 호출하면, 수신자의 FCM
// 토큰으로 푸시를 보낸다. Firestore 트리거(Cloud Functions)가 없는 무예산
// 구조라, 발송 주체는 이벤트를 만든 클라이언트 + Admin SDK를 든 이 백엔드다.
// 실제 발송 규칙(차단·알림 설정·죽은 토큰 정리)은 _push.js가 담당한다.
module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  const decoded = await requireUser(req, res);
  if (!decoded) return;

  const { type, title, body, data } = req.body || {};
  if (!type) return res.status(400).json({ error: 'missing-type' });

  // 수신자 결정: 관리자 알림이면 이메일로 관리자 uid를 찾고, 아니면 body의 값.
  let recipientUid;
  if (ADMIN_TYPES.has(type)) {
    try {
      const adminUser = await admin.auth().getUserByEmail(ADMIN_EMAIL);
      recipientUid = adminUser.uid;
    } catch (e) {
      return res.status(200).json({ ok: true, skipped: 'no-admin-account' });
    }
  } else {
    recipientUid = req.body && req.body.recipientUid;
  }
  if (!recipientUid) return res.status(400).json({ error: 'missing-recipient' });

  const result = await sendPushToUser(admin, {
    recipientUid,
    senderUid: decoded.uid,
    type,
    title,
    body,
    data,
  });

  if (result.skipped) return res.status(200).json({ ok: true, skipped: result.skipped });
  return res.status(200).json({ ok: true, sent: result.sent, failed: result.failed });
};
