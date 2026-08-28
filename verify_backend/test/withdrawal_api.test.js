// 탈퇴 후 재가입 제한(withdraw / signup-eligibility / send-code 관문) 테스트.
// Firebase Auth/Firestore는 로컬 에뮬레이터를 쓰고 이메일 발송은 목으로 바꾼다.
const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  mockReq,
  mockRes,
  signUpTestUser,
  signUpVerifiedTestUser,
} = require('./helpers');

const AUTH_EMULATOR_HOST = '127.0.0.1:9099';
const FIRESTORE_EMULATOR_HOST = '127.0.0.1:8085';
const PROJECT_ID = 'demo-yeogi-itdae';

process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_EMULATOR_HOST;
process.env.FIRESTORE_EMULATOR_HOST = FIRESTORE_EMULATOR_HOST;
process.env.GCLOUD_PROJECT = PROJECT_ID;

let admin;
let emailKey;
const sentEmails = [];
const DAY_MS = 24 * 60 * 60 * 1000;

before((t) => {
  // send-code.js가 require('nodemailer')를 하기 전에 목으로 바꿔치기한다.
  t.mock.module('nodemailer', {
    exports: {
      createTransport: () => ({
        sendMail: async (options) => {
          sentEmails.push(options);
          return { messageId: 'fake-message-id' };
        },
      }),
    },
  });
  admin = require('../_admin');
  ({ emailKey } = require('../_withdrawal'));
});

beforeEach(async () => {
  sentEmails.length = 0;
  await Promise.all([
    fetch(
      `http://${FIRESTORE_EMULATOR_HOST}/emulator/v1/projects/${PROJECT_ID}/databases/(default)/documents`,
      { method: 'DELETE' },
    ),
    fetch(`http://${AUTH_EMULATOR_HOST}/emulator/v1/projects/${PROJECT_ID}/accounts`, {
      method: 'DELETE',
    }),
  ]);
});

/** 이 이메일이 daysFromNow 뒤까지 제한된 상태로 만들어둔다. */
async function seedWithdrawal(email, daysFromNow) {
  await admin
    .firestore()
    .collection('withdrawnUsers')
    .doc(emailKey(email))
    .set({
      withdrawnAt: admin.firestore.Timestamp.fromMillis(Date.now()),
      reregisterAllowedAt: admin.firestore.Timestamp.fromMillis(
        Date.now() + daysFromNow * DAY_MS,
      ),
    });
}

// ---------------------------------------------------------------------------
// /api/withdraw
// ---------------------------------------------------------------------------

test('withdraw: 인증 토큰이 없으면 401', async () => {
  const withdraw = require('../api/withdraw');
  const res = mockRes();
  await withdraw(mockReq({}), res);
  assert.equal(res.statusCode, 401);
});

test('withdraw: 재가입 제한 기록이 남고 Auth 계정이 삭제된다', async () => {
  const withdraw = require('../api/withdraw');
  const email = 'quit@hallym.ac.kr';
  const { idToken, localId } = await signUpTestUser(email, 'password123');

  const res = mockRes();
  await withdraw(mockReq({ headers: { authorization: `Bearer ${idToken}` } }), res);
  assert.equal(res.statusCode, 200);

  const doc = await admin
    .firestore()
    .collection('withdrawnUsers')
    .doc(emailKey(email))
    .get();
  assert.ok(doc.exists, '탈퇴 기록이 남아야 한다');

  // 기록에 평문 이메일을 남기지 않는다.
  assert.equal(doc.data().email, undefined);

  // 30일 뒤쯤으로 잡혀 있어야 한다(초 단위 오차 허용).
  const allowedAtMs = doc.data().reregisterAllowedAt.toMillis();
  const expected = Date.now() + 30 * DAY_MS;
  assert.ok(Math.abs(allowedAtMs - expected) < 60 * 1000);

  await assert.rejects(() => admin.auth().getUser(localId), '계정이 삭제돼야 한다');
});

test('withdraw: 탈퇴자가 남긴 신고 기록도 함께 정리된다', async () => {
  const withdraw = require('../api/withdraw');
  const { idToken, localId } = await signUpTestUser('quit2@hallym.ac.kr', 'password123');
  const db = admin.firestore();
  await db.collection('reports').doc('item1_' + localId).set({ reporterUid: localId });
  await db.collection('reports').doc('item1_other').set({ reporterUid: 'other-uid' });

  await withdraw(
    mockReq({ headers: { authorization: `Bearer ${idToken}` } }),
    mockRes(),
  );

  const mine = await db.collection('reports').doc('item1_' + localId).get();
  const other = await db.collection('reports').doc('item1_other').get();
  assert.equal(mine.exists, false, '본인 신고는 지워져야 한다');
  assert.equal(other.exists, true, '다른 사람 신고는 남아야 한다');
});

test('withdraw removes all server-owned user data across batches', async () => {
  const withdraw = require('../api/withdraw');
  const { idToken, localId } = await signUpTestUser(
    'cleanup@hallym.ac.kr',
    'password123',
  );
  const db = admin.firestore();

  const queriedCollections = [
    ['items', 'authorUid'],
    ['reports', 'reporterUid'],
    ['bugReports', 'reporterUid'],
    ['reportAppeals', 'authorUid'],
  ];
  await Promise.all(
    queriedCollections.flatMap(([collection, ownerField]) => [
      db.collection(collection).doc(`mine-${collection}`).set({
        [ownerField]: localId,
      }),
      db.collection(collection).doc(`other-${collection}`).set({
        [ownerField]: 'other-uid',
      }),
    ]),
  );

  // Exercise the second cleanup page beyond the 450-write safety margin.
  const notificationBatch = db.batch();
  for (let i = 0; i < 451; i += 1) {
    notificationBatch.set(db.collection('notifications').doc(`mine-${i}`), {
      recipientUid: localId,
    });
  }
  await notificationBatch.commit();
  await db.collection('notifications').doc('other-notification').set({
    recipientUid: 'other-uid',
  });
  await db.collection('notifications').doc('sent-notification').set({
    recipientUid: 'other-uid',
    senderUid: localId,
  });
  await db.collection('reports').doc('authored-report').set({
    reporterUid: 'other-uid',
    authorUid: localId,
  });

  await db.collection('chats').doc('shared-chat').set({
    participants: [localId, 'other-uid'],
    participantNicknames: { [localId]: '탈퇴 전 닉네임', 'other-uid': '상대방' },
    revealedRealNames: { [localId]: '홍길동 (20240001)' },
    typing: { [localId]: true, 'other-uid': false },
    unreadCount: { [localId]: 3, 'other-uid': 1 },
    clearedAt: { [localId]: admin.firestore.Timestamp.now() },
    lastReadAt: { [localId]: admin.firestore.Timestamp.now() },
    itemAuthorUid: localId,
    lastMessage: '탈퇴자가 보낸 마지막 메시지',
  });
  await db
    .collection('chats')
    .doc('shared-chat')
    .collection('messages')
    .doc('mine')
    .set({ senderUid: localId, type: 'text', text: '삭제 대상' });
  await db
    .collection('chats')
    .doc('shared-chat')
    .collection('messages')
    .doc('other')
    .set({
      senderUid: 'other-uid',
      type: 'text',
      text: '남는 메시지',
      createdAt: admin.firestore.Timestamp.now(),
    });

  const directCollections = [
    'userPrivate',
    'blocks',
    'bookmarks',
    'userPublicProfiles',
    'userSettings',
    'savedSearches',
    'fcmTokens',
  ];
  await Promise.all(
    directCollections.flatMap((collection) => [
      db.collection(collection).doc(localId).set({ owner: localId }),
      db.collection(collection).doc('other-uid').set({ owner: 'other-uid' }),
    ]),
  );

  const res = mockRes();
  await withdraw(
    mockReq({ headers: { authorization: `Bearer ${idToken}` } }),
    res,
  );
  assert.equal(res.statusCode, 200);

  for (const [collection] of queriedCollections) {
    assert.equal(
      (await db.collection(collection).doc(`mine-${collection}`).get()).exists,
      false,
      `${collection}: caller-owned document should be deleted`,
    );
    assert.equal(
      (await db.collection(collection).doc(`other-${collection}`).get()).exists,
      true,
      `${collection}: another user's document should remain`,
    );
  }
  assert.equal(
    (
      await db
        .collection('notifications')
        .where('recipientUid', '==', localId)
        .get()
    ).size,
    0,
  );
  assert.equal(
    (await db.collection('notifications').doc('other-notification').get()).exists,
    true,
  );
  assert.equal(
    (await db.collection('notifications').doc('sent-notification').get()).exists,
    false,
  );
  assert.equal(
    (await db.collection('reports').doc('authored-report').get()).exists,
    false,
  );

  const anonymizedChat = (
    await db.collection('chats').doc('shared-chat').get()
  ).data();
  const tombstoneUid = anonymizedChat.participants.find(
    (participant) => participant !== 'other-uid',
  );
  assert.match(tombstoneUid, /^deleted_[0-9a-f]{24}$/);
  assert.equal(anonymizedChat.participants.includes(localId), false);
  assert.equal(anonymizedChat.participantNicknames[localId], undefined);
  assert.equal(anonymizedChat.participantNicknames[tombstoneUid], '탈퇴한 사용자');
  assert.equal(anonymizedChat.revealedRealNames?.[localId], undefined);
  assert.equal(anonymizedChat.typing?.[localId], undefined);
  assert.equal(anonymizedChat.unreadCount?.[localId], undefined);
  assert.equal(anonymizedChat.clearedAt?.[localId], undefined);
  assert.equal(anonymizedChat.lastReadAt?.[localId], undefined);
  assert.equal(anonymizedChat.itemAuthorUid, tombstoneUid);
  assert.equal(anonymizedChat.itemDeleted, true);
  assert.equal(anonymizedChat.lastMessage, '남는 메시지');
  assert.equal(
    (
      await db
        .collection('chats')
        .doc('shared-chat')
        .collection('messages')
        .doc('mine')
        .get()
    ).exists,
    false,
  );
  assert.equal(
    (
      await db
        .collection('chats')
        .doc('shared-chat')
        .collection('messages')
        .doc('other')
        .get()
    ).exists,
    true,
  );

  for (const collection of directCollections) {
    assert.equal(
      (await db.collection(collection).doc(localId).get()).exists,
      false,
      `${collection}: caller-owned document should be deleted`,
    );
    assert.equal(
      (await db.collection(collection).doc('other-uid').get()).exists,
      true,
      `${collection}: another user's document should remain`,
    );
  }
});

// ---------------------------------------------------------------------------
// /api/send-code — 실제 차단 관문
// ---------------------------------------------------------------------------

test('send-code: 재가입 제한 기간이면 403과 남은 일수를 돌려준다', async () => {
  const sendCode = require('../api/send-code');
  const email = 'blocked@hallym.ac.kr';
  await seedWithdrawal(email, 10);
  const { idToken } = await signUpTestUser(email, 'password123');

  const res = mockRes();
  await sendCode(mockReq({ headers: { authorization: `Bearer ${idToken}` } }), res);

  assert.equal(res.statusCode, 403);
  assert.equal(res._json.error, 'withdrawn-cooldown');
  assert.equal(res._json.daysLeft, 10);
  assert.equal(sentEmails.length, 0, '제한 중에는 인증 메일을 보내면 안 된다');
});

test('send-code: 제한에 걸리면 방금 만든 계정과 프로필 문서를 되돌린다', async () => {
  const sendCode = require('../api/send-code');
  const email = 'rollback@hallym.ac.kr';
  await seedWithdrawal(email, 5);
  const { idToken, localId } = await signUpTestUser(email, 'password123');

  // 가입 과정에서 클라이언트가 먼저 써둔 프로필 문서들.
  const db = admin.firestore();
  await db.collection('userPublicProfiles').doc(localId).set({ nickname: '되돌림' });
  await db.collection('userPrivate').doc(localId).set({ realName: '홍길동' });

  await sendCode(mockReq({ headers: { authorization: `Bearer ${idToken}` } }), mockRes());

  await assert.rejects(
    () => admin.auth().getUser(localId),
    '껍데기 계정이 남으면 그 이메일은 인증도 재가입도 못 하게 묶인다',
  );
  assert.equal((await db.collection('userPublicProfiles').doc(localId).get()).exists, false);
  assert.equal((await db.collection('userPrivate').doc(localId).get()).exists, false);
});

test('send-code: 제한 기간이 지났으면 정상 발송되고 만료된 기록은 지워진다', async () => {
  const sendCode = require('../api/send-code');
  const email = 'expired@hallym.ac.kr';
  await seedWithdrawal(email, -1); // 어제 만료
  const { idToken } = await signUpTestUser(email, 'password123');

  const res = mockRes();
  await sendCode(mockReq({ headers: { authorization: `Bearer ${idToken}` } }), res);

  assert.equal(res.statusCode, 200);
  assert.equal(sentEmails.length, 1);
  const doc = await admin
    .firestore()
    .collection('withdrawnUsers')
    .doc(emailKey(email))
    .get();
  assert.equal(doc.exists, false, '만료된 기록은 확인하는 김에 정리한다');
});

test('send-code: 이미 인증된 계정은 제한 검사를 타지 않는다', async () => {
  const sendCode = require('../api/send-code');
  const email = 'verified@hallym.ac.kr';
  await seedWithdrawal(email, 10);
  const { idToken, localId } = await signUpVerifiedTestUser(
    admin,
    email,
    'password123',
  );

  const res = mockRes();
  await sendCode(mockReq({ headers: { authorization: `Bearer ${idToken}` } }), res);

  assert.equal(res.statusCode, 200);
  // 인증까지 끝난 계정을 실수로 지워버리면 안 된다.
  assert.ok(await admin.auth().getUser(localId));
});

// ---------------------------------------------------------------------------
// /api/signup-eligibility — 가입 화면의 사전 안내
// ---------------------------------------------------------------------------

test('signup-eligibility: 제한 중이면 allowed:false와 남은 일수를 준다', async () => {
  const eligibility = require('../api/signup-eligibility');
  const email = 'pre@hallym.ac.kr';
  await seedWithdrawal(email, 7);

  const res = mockRes();
  await eligibility(mockReq({ body: { email } }), res);

  assert.equal(res.statusCode, 200);
  assert.equal(res._json.allowed, false);
  assert.equal(res._json.daysLeft, 7);
});

test('signup-eligibility: 탈퇴 기록이 없으면 allowed:true', async () => {
  const eligibility = require('../api/signup-eligibility');
  const res = mockRes();
  await eligibility(mockReq({ body: { email: 'fresh@hallym.ac.kr' } }), res);

  assert.equal(res.statusCode, 200);
  assert.equal(res._json.allowed, true);
  assert.equal(res._json.daysLeft, 0);
});

test('signup-eligibility: 한림대 이메일이 아니면 403', async () => {
  const eligibility = require('../api/signup-eligibility');
  const res = mockRes();
  await eligibility(mockReq({ body: { email: 'someone@gmail.com' } }), res);
  assert.equal(res.statusCode, 403);
  assert.equal(res._json.error, 'domain-not-allowed');
});

test('signup-eligibility: 대소문자가 달라도 같은 명의로 본다', async () => {
  const eligibility = require('../api/signup-eligibility');
  await seedWithdrawal('mixed@hallym.ac.kr', 3);

  const res = mockRes();
  await eligibility(mockReq({ body: { email: 'MIXED@Hallym.ac.kr' } }), res);
  assert.equal(res._json.allowed, false);
});
