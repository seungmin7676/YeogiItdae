const { initAdmin, setCors, requireUser } = require('../_lib');

// firestore.rules / lib/services/admin.dart 의 관리자 이메일과 반드시 일치시킨다.
const ADMIN_EMAIL = '20225216@hallym.ac.kr';

// 알림 종류 → userSettings 필드. 여기 없는 종류(관리자 알림 등)는 설정 필터를
// 타지 않고 항상 보낸다. (lib/screens/notifications_screen.dart 와 동일한 매핑)
const TYPE_TO_SETTING = {
  chat_started: 'notifyChatStarted',
  chat_message: 'notifyChatMessage',
  keyword_match: 'notifyKeywordMatch',
  report_result: 'notifyReportResult',
  item_hidden: 'notifyItemHidden',
  item_removed: 'notifyItemHidden',
};

// 관리자에게 보내는 알림 종류. recipientUid 없이 서버가 관리자로 라우팅한다.
const ADMIN_TYPES = new Set(['report_received', 'bug_report']);

// 클라이언트가 이벤트를 일으킨 직후 이 엔드포인트를 호출하면, 수신자의 FCM
// 토큰으로 푸시를 보낸다. Firestore 트리거(Cloud Functions)가 없는 무예산
// 구조라, 발송 주체는 이벤트를 만든 클라이언트 + Admin SDK를 든 이 백엔드다.
module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  const decoded = await requireUser(req, res);
  if (!decoded) return;

  const { type, title, body, data } = req.body || {};
  if (!type) return res.status(400).json({ error: 'missing-type' });

  const db = admin.firestore();

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

  // 나 자신에게는 보내지 않는다.
  if (recipientUid === decoded.uid) {
    return res.status(200).json({ ok: true, skipped: 'self' });
  }

  // 수신자가 발신자를 차단했으면 보내지 않는다(차단 사실이 드러나지 않도록
  // 조용히 건너뛴다 — 앱의 다른 차단 처리와 동일한 원칙).
  const blockDoc = await db.collection('blocks').doc(recipientUid).get();
  const blockedUsers = (blockDoc.exists && blockDoc.data().blockedUsers) || {};
  if (blockedUsers[decoded.uid]) {
    return res.status(200).json({ ok: true, skipped: 'blocked' });
  }

  // 수신자가 이 종류의 알림을 껐으면 보내지 않는다(기본값은 켜짐).
  const settingField = TYPE_TO_SETTING[type];
  if (settingField) {
    const settingsDoc = await db.collection('userSettings').doc(recipientUid).get();
    const settings = (settingsDoc.exists && settingsDoc.data()) || {};
    if (settings[settingField] === false) {
      return res.status(200).json({ ok: true, skipped: 'muted' });
    }
  }

  // 수신자의 기기 토큰들.
  const tokenDoc = await db.collection('fcmTokens').doc(recipientUid).get();
  const tokens = (tokenDoc.exists && tokenDoc.data().tokens) || [];
  if (!Array.isArray(tokens) || tokens.length === 0) {
    return res.status(200).json({ ok: true, skipped: 'no-tokens' });
  }

  // FCM data 페이로드는 모든 값이 문자열이어야 한다.
  const stringData = { type: String(type) };
  if (data && typeof data === 'object') {
    for (const [k, v] of Object.entries(data)) {
      if (v !== null && v !== undefined) stringData[k] = String(v);
    }
  }

  const message = {
    tokens,
    notification: {
      title: title ? String(title) : undefined,
      body: body ? String(body) : undefined,
    },
    data: stringData,
    android: { priority: 'high', notification: { channelId: 'high_importance_channel' } },
    apns: { payload: { aps: { sound: 'default' } } },
  };

  const response = await admin.messaging().sendEachForMulticast(message);

  // 더 이상 유효하지 않은 토큰은 정리해, 다음 발송부터 빼둔다.
  const staleTokens = [];
  response.responses.forEach((r, i) => {
    if (
      !r.success &&
      r.error &&
      (r.error.code === 'messaging/registration-token-not-registered' ||
        r.error.code === 'messaging/invalid-registration-token' ||
        r.error.code === 'messaging/invalid-argument')
    ) {
      staleTokens.push(tokens[i]);
    }
  });
  if (staleTokens.length > 0) {
    await db
      .collection('fcmTokens')
      .doc(recipientUid)
      .set(
        { tokens: admin.firestore.FieldValue.arrayRemove(...staleTokens) },
        { merge: true },
      );
  }

  return res.status(200).json({
    ok: true,
    sent: response.successCount,
    failed: response.failureCount,
  });
};
