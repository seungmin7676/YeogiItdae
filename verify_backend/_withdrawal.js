const crypto = require('crypto');

// ---------------------------------------------------------------------------
// 탈퇴 후 재가입 제한
//
// 탈퇴한 계정과 **같은 명의(학교 이메일 = 학번)** 로는 일정 기간 다시 가입할 수
// 없게 한다. 차단·신고를 피하려고 탈퇴 후 곧바로 새 계정을 만드는 것을 막는 게
// 목적이다.
//
// 왜 백엔드인가: Firestore 보안 규칙은 Auth 계정 생성 자체를 막을 수 없고,
// 클라이언트 검사는 우회할 수 있다. 이 앱에서 계정이 실제로 쓸모를 갖는 시점은
// **이메일 인증(send-code → verify-code)** 이고 그 관문이 이 백엔드이므로,
// 여기서 막으면 우회해서 만든 계정도 아무것도 할 수 없다
// (firestore.rules의 isVerifiedHallymUser()가 email_verified를 요구한다).
// ---------------------------------------------------------------------------

/** 재가입이 가능해지기까지의 기간(일). 정책을 바꾸려면 이 값만 고치면 된다. */
const WITHDRAWAL_COOLDOWN_DAYS = 30;

const COLLECTION = 'withdrawnUsers';
const DAY_MS = 24 * 60 * 60 * 1000;

/**
 * 이메일을 문서 ID로 쓸 해시로 바꾼다.
 *
 * 탈퇴자 명단을 평문 이메일로 쌓아두지 않기 위해서다. 학번 이메일은 자릿수가
 * 정해져 있어 해시만으로 강한 익명성이 보장되지는 않지만, 이 컬렉션은 보안
 * 규칙에서 클라이언트 접근을 전부 막고 Admin SDK로만 읽으므로 노출 경로 자체가
 * 없다. 평문을 그대로 남기지 않는 것만으로 충분하다고 봤다.
 */
function emailKey(email) {
  return crypto
    .createHash('sha256')
    .update(String(email || '').trim().toLowerCase())
    .digest('hex');
}

/**
 * 남은 제한 일수를 올림해서 돌려준다(0이면 제한 없음).
 * "3일 뒤에 가입할 수 있어요"처럼 사용자에게 보여줄 값이라, 12시간 남았으면
 * 0일이 아니라 1일로 말해야 한다.
 */
function daysLeftUntil(allowedAtMs, nowMs) {
  const remaining = allowedAtMs - nowMs;
  if (remaining <= 0) return 0;
  return Math.ceil(remaining / DAY_MS);
}

/** 탈퇴 시각을 기록한다. 같은 이메일로 다시 탈퇴하면 기간이 갱신된다. */
async function recordWithdrawal(admin, email) {
  const now = Date.now();
  const allowedAtMs = now + WITHDRAWAL_COOLDOWN_DAYS * DAY_MS;
  await admin
    .firestore()
    .collection(COLLECTION)
    .doc(emailKey(email))
    .set({
      withdrawnAt: admin.firestore.Timestamp.fromMillis(now),
      reregisterAllowedAt: admin.firestore.Timestamp.fromMillis(allowedAtMs),
    });
  return { allowedAtMs, daysLeft: WITHDRAWAL_COOLDOWN_DAYS };
}

/**
 * 이 이메일이 아직 재가입 제한 기간인지 확인한다.
 * 기간이 지난 기록은 그 자리에서 지워, 탈퇴자 명단을 필요 이상으로 오래
 * 들고 있지 않는다.
 *
 * @returns {Promise<{blocked: boolean, daysLeft: number}>}
 */
async function checkWithdrawalCooldown(admin, email) {
  const ref = admin.firestore().collection(COLLECTION).doc(emailKey(email));
  const doc = await ref.get();
  if (!doc.exists) return { blocked: false, daysLeft: 0 };

  const allowedAt = doc.data().reregisterAllowedAt;
  const allowedAtMs = allowedAt?.toMillis?.() ?? 0;
  const daysLeft = daysLeftUntil(allowedAtMs, Date.now());
  if (daysLeft <= 0) {
    // 제한이 끝났으면 기록을 남겨둘 이유가 없다.
    await ref.delete().catch(() => {});
    return { blocked: false, daysLeft: 0 };
  }
  return { blocked: true, daysLeft };
}

/** 탈퇴자가 남긴 신고 기록을 지운다(reports는 클라이언트가 접근할 수 없다). */
async function deleteReportsBy(admin, uid) {
  const db = admin.firestore();
  const snap = await db.collection('reports').where('reporterUid', '==', uid).get();
  if (snap.empty) return 0;
  const batch = db.batch();
  snap.docs.forEach((doc) => batch.delete(doc.ref));
  await batch.commit();
  return snap.size;
}

module.exports = {
  WITHDRAWAL_COOLDOWN_DAYS,
  emailKey,
  daysLeftUntil,
  recordWithdrawal,
  checkWithdrawalCooldown,
  deleteReportsBy,
};
