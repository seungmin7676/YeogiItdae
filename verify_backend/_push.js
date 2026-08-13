// 한 사용자에게 FCM 푸시를 보내는 공통 로직. send-push(단건)와
// notify-matches(구독자 다건)가 같은 규칙(차단·알림 설정·죽은 토큰 정리)을
// 쓰도록 한곳에 모았다.

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

/**
 * 수신자에게 푸시를 보낸다. 보내지 않은 경우에도 예외를 던지지 않고
 * { skipped } 로 이유를 돌려준다(차단 사실이 호출자에게 드러나지 않도록,
 * 호출자는 이 값을 사용자에게 그대로 노출하면 안 된다).
 */
async function sendPushToUser(
  admin,
  { recipientUid, senderUid, type, title, body, data },
) {
  const db = admin.firestore();

  if (!recipientUid) return { skipped: 'no-recipient' };
  // 나 자신에게는 보내지 않는다.
  if (recipientUid === senderUid) return { skipped: 'self' };

  // 수신자가 발신자를 차단했으면 보내지 않는다(차단 사실이 드러나지 않도록
  // 조용히 건너뛴다 — 앱의 다른 차단 처리와 동일한 원칙).
  const blockDoc = await db.collection('blocks').doc(recipientUid).get();
  const blockedUsers = (blockDoc.exists && blockDoc.data().blockedUsers) || {};
  if (senderUid && blockedUsers[senderUid]) return { skipped: 'blocked' };

  // 수신자가 이 종류의 알림을 껐으면 보내지 않는다(기본값은 켜짐).
  const settingField = TYPE_TO_SETTING[type];
  if (settingField) {
    const settingsDoc = await db.collection('userSettings').doc(recipientUid).get();
    const settings = (settingsDoc.exists && settingsDoc.data()) || {};
    if (settings[settingField] === false) return { skipped: 'muted' };
  }

  // 수신자의 기기 토큰들.
  const tokenDoc = await db.collection('fcmTokens').doc(recipientUid).get();
  const tokens = (tokenDoc.exists && tokenDoc.data().tokens) || [];
  if (!Array.isArray(tokens) || tokens.length === 0) {
    return { skipped: 'no-tokens' };
  }

  // FCM data 페이로드는 모든 값이 문자열이어야 한다.
  const stringData = { type: String(type) };
  if (data && typeof data === 'object') {
    for (const [k, v] of Object.entries(data)) {
      if (v !== null && v !== undefined) stringData[k] = String(v);
    }
  }

  const response = await admin.messaging().sendEachForMulticast({
    tokens,
    notification: {
      title: title ? String(title) : undefined,
      body: body ? String(body) : undefined,
    },
    data: stringData,
    android: { priority: 'high', notification: { channelId: 'high_importance_channel' } },
    apns: { payload: { aps: { sound: 'default' } } },
  });

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

  return { sent: response.successCount, failed: response.failureCount };
}

module.exports = { sendPushToUser, TYPE_TO_SETTING };
