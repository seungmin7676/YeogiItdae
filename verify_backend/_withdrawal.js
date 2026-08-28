const crypto = require('crypto');
const { deleteCloudinaryUrls } = require('./_cloudinary');

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
const DELETE_BATCH_SIZE = 450;

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
  return deleteQueryInBatches(
    db,
    db.collection('reports').where('reporterUid', '==', uid),
  );
}

/** Firestore의 500 write 제한을 넘지 않도록 같은 query를 반복해서 비운다. */
async function deleteQueryInBatches(db, query) {
  let deleted = 0;
  while (true) {
    const snap = await query.limit(DELETE_BATCH_SIZE).get();
    if (snap.empty) return deleted;

    const batch = db.batch();
    snap.docs.forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deleted += snap.size;
  }
}

/**
 * 탈퇴 계정이 단독 소유하는 Firestore 데이터를 서버 권한으로 정리한다.
 *
 * 모든 삭제는 없는 문서에 다시 실행해도 안전하다. 따라서 요청이 중간에 실패해도
 * 계정이 남아 있는 동안 같은 탈퇴 요청으로 나머지 정리를 재시도할 수 있다.
 * 상대방과 공유하는 채팅방 껍데기는 제품 정책상 익명화해 보존한다. 다만 탈퇴자가
 * 보낸 메시지와 계정을 직접 식별하는 uid/map 항목은 이 경계에서 제거한다.
 */
async function deleteUserOwnedData(admin, uid) {
  const db = admin.firestore();
  const ownedItems = await db.collection('items').where('authorUid', '==', uid).get();
  const publicProfile = await db.collection('userPublicProfiles').doc(uid).get();
  const sentMessages = await db
    .collectionGroup('messages')
    .where('senderUid', '==', uid)
    .get();
  const mediaUrls = [];
  for (const doc of ownedItems.docs) {
    const images = doc.data().imageUrls;
    if (Array.isArray(images)) mediaUrls.push(...images);
  }
  if (publicProfile.exists && publicProfile.data().photoUrl) {
    mediaUrls.push(publicProfile.data().photoUrl);
  }
  for (const doc of sentMessages.docs) {
    if (doc.data().type === 'image' && doc.data().imageUrl) {
      mediaUrls.push(doc.data().imageUrl);
    }
  }
  // Firestore 참조를 지우기 전에 원본 미디어를 먼저 지운다. 외부 저장소 삭제가
  // 실패하면 탈퇴를 실패 처리해 사용자가 재시도할 수 있고 고아 파일이 남지 않는다.
  await deleteCloudinaryUrls(mediaUrls);

  const ownedQueries = [
    db.collection('notifications').where('recipientUid', '==', uid),
    db.collection('notifications').where('senderUid', '==', uid),
    db.collection('reports').where('reporterUid', '==', uid),
    db.collection('reports').where('authorUid', '==', uid),
    db.collection('bugReports').where('reporterUid', '==', uid),
    db.collection('reportAppeals').where('authorUid', '==', uid),
  ];

  let deleted = 0;
  for (let i = 0; i < ownedItems.docs.length; i += DELETE_BATCH_SIZE) {
    const batch = db.batch();
    ownedItems.docs
      .slice(i, i + DELETE_BATCH_SIZE)
      .forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deleted += Math.min(DELETE_BATCH_SIZE, ownedItems.docs.length - i);
  }
  // 공유 채팅방 껍데기는 상대방 화면을 위해 남기되, 탈퇴자가 보낸 텍스트와
  // 이미지 메시지는 모두 제거한다.
  for (let i = 0; i < sentMessages.docs.length; i += DELETE_BATCH_SIZE) {
    const batch = db.batch();
    sentMessages.docs
      .slice(i, i + DELETE_BATCH_SIZE)
      .forEach((doc) => batch.delete(doc.ref));
    await batch.commit();
    deleted += Math.min(DELETE_BATCH_SIZE, sentMessages.docs.length - i);
  }
  for (const query of ownedQueries) {
    deleted += await deleteQueryInBatches(db, query);
  }

  const directCollections = [
    'userPrivate',
    'blocks',
    'bookmarks',
    'userPublicProfiles',
    'userSettings',
    'savedSearches',
    'fcmTokens',
  ];
  const batch = db.batch();
  directCollections.forEach((name) => batch.delete(db.collection(name).doc(uid)));
  await batch.commit();

  // 상대방과 공유되는 채팅방 자체는 남기되 공개 프로필 스냅샷과 실명 공개값은
  // 익명화한다. 참가자 배열에 있던 uid도 난수 표식으로 치환해, 남은 채팅 문서가
  // 삭제된 Auth 계정을 직접 가리키지 않게 한다.
  const chats = await db.collection('chats').where('participants', 'array-contains', uid).get();
  const anonymousUid = `deleted_${crypto.randomBytes(12).toString('hex')}`;
  for (let i = 0; i < chats.docs.length; i += DELETE_BATCH_SIZE) {
    const chatBatch = db.batch();
    for (const doc of chats.docs.slice(i, i + DELETE_BATCH_SIZE)) {
      const chat = doc.data();
      const latest = await doc.ref
        .collection('messages')
        .orderBy('createdAt', 'desc')
        .limit(1)
        .get();
      const last = latest.empty ? null : latest.docs[0].data();
      const lastMessage = last == null
        ? '탈퇴한 사용자의 메시지가 삭제됐습니다'
        : last.type === 'image'
          ? '사진을 보냈습니다'
          : String(last.text || '메시지');
      const update = {
        participants: Array.isArray(chat.participants)
          ? chat.participants.map((participant) =>
              participant === uid ? anonymousUid : participant)
          : [],
        [`participantNicknames.${uid}`]: admin.firestore.FieldValue.delete(),
        [`participantNicknames.${anonymousUid}`]: '탈퇴한 사용자',
        [`revealedRealNames.${uid}`]: admin.firestore.FieldValue.delete(),
        [`typing.${uid}`]: admin.firestore.FieldValue.delete(),
        [`typing.${anonymousUid}`]: false,
        [`unreadCount.${uid}`]: admin.firestore.FieldValue.delete(),
        [`clearedAt.${uid}`]: admin.firestore.FieldValue.delete(),
        [`lastReadAt.${uid}`]: admin.firestore.FieldValue.delete(),
        lastMessage,
        lastMessageAt: last?.createdAt || admin.firestore.FieldValue.serverTimestamp(),
      };
      if (chat.itemAuthorUid === uid) {
        update.itemAuthorUid = anonymousUid;
        update.itemDeleted = true;
      }
      chatBatch.update(doc.ref, update);
    }
    await chatBatch.commit();
  }

  return deleted + directCollections.length + chats.size;
}

module.exports = {
  WITHDRAWAL_COOLDOWN_DAYS,
  emailKey,
  daysLeftUntil,
  recordWithdrawal,
  checkWithdrawalCooldown,
  deleteReportsBy,
  deleteUserOwnedData,
};
