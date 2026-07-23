// verify_backend의 이메일 인증/비밀번호 재설정/탈퇴 API 테스트.
//
// 실제 이메일 발송(nodemailer)은 목으로 대체하고, Firebase Auth/Firestore는
// 로컬 에뮬레이터를 사용한다(실제 자격 증명이 전혀 필요 없다). `npm test`로
// 실행한다.
const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const crypto = require('node:crypto');
const { mockReq, mockRes, signUpTestUser } = require('./helpers');

const AUTH_EMULATOR_HOST = '127.0.0.1:9099';
const FIRESTORE_EMULATOR_HOST = '127.0.0.1:8085';
const PROJECT_ID = 'demo-yeogi-itdae';

process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_EMULATOR_HOST;
process.env.FIRESTORE_EMULATOR_HOST = FIRESTORE_EMULATOR_HOST;
process.env.GCLOUD_PROJECT = PROJECT_ID;

let admin;
const sentEmails = [];

before((t) => {
  // send-code.js / send-reset-code.js가 require('nodemailer')를 하기 전에
  // 먼저 목으로 바꿔치기해야 한다.
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

  admin = require('firebase-admin');
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

test('send-code: 인증 토큰이 없으면 401', async () => {
  const sendCode = require('../api/send-code');
  const res = mockRes();
  await sendCode(mockReq({}), res);
  assert.equal(res.statusCode, 401);
});

test('send-code: 한림대 이메일이 아니면 403', async () => {
  const sendCode = require('../api/send-code');
  const { idToken } = await signUpTestUser('alice@gmail.com', 'password123');
  const res = mockRes();
  await sendCode(mockReq({ headers: { authorization: `Bearer ${idToken}` } }), res);
  assert.equal(res.statusCode, 403);
  assert.equal(res._json.error, 'domain-not-allowed');
});

test('send-code: 한림대 이메일이면 메일이 발송되고 Firestore에 코드가 기록된다', async () => {
  const sendCode = require('../api/send-code');
  const { idToken, localId } = await signUpTestUser('bob@hallym.ac.kr', 'password123');
  const res = mockRes();
  await sendCode(mockReq({ headers: { authorization: `Bearer ${idToken}` } }), res);

  assert.equal(res.statusCode, 200);
  assert.equal(sentEmails.length, 1);
  assert.match(sentEmails[0].text, /\d{6}/);

  const doc = await admin.firestore().collection('emailVerificationCodes').doc(localId).get();
  assert.ok(doc.exists);
  assert.equal(doc.data().email, 'bob@hallym.ac.kr');
});

test('send-code: 60초 이내 재요청은 쿨다운(429)으로 막힌다', async () => {
  const sendCode = require('../api/send-code');
  const { idToken } = await signUpTestUser('carol@hallym.ac.kr', 'password123');
  const req = mockReq({ headers: { authorization: `Bearer ${idToken}` } });
  await sendCode(req, mockRes());

  const res2 = mockRes();
  await sendCode(req, res2);
  assert.equal(res2.statusCode, 429);
  assert.equal(res2._json.error, 'cooldown');
  assert.equal(sentEmails.length, 1, '쿨다운에 걸리면 메일을 다시 보내면 안 된다');
});

test('verify-code: 올바른 코드면 이메일 인증이 완료되고 코드 문서가 삭제된다', async () => {
  const { idToken, localId } = await signUpTestUser('dave@hallym.ac.kr', 'password123');
  const db = admin.firestore();
  await db
    .collection('emailVerificationCodes')
    .doc(localId)
    .set({
      code: '123456',
      email: 'dave@hallym.ac.kr',
      attempts: 0,
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
      lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  const verifyCode = require('../api/verify-code');
  const res = mockRes();
  await verifyCode(
    mockReq({
      body: { code: '123456' },
      headers: { authorization: `Bearer ${idToken}` },
    }),
    res,
  );

  assert.equal(res.statusCode, 200);
  const after = await db.collection('emailVerificationCodes').doc(localId).get();
  assert.equal(after.exists, false);
  const userRecord = await admin.auth().getUser(localId);
  assert.equal(userRecord.emailVerified, true);
});

test('verify-code: 틀린 코드는 400이고 시도 횟수가 늘어난다', async () => {
  const { idToken, localId } = await signUpTestUser('erin@hallym.ac.kr', 'password123');
  const db = admin.firestore();
  await db
    .collection('emailVerificationCodes')
    .doc(localId)
    .set({
      code: '654321',
      email: 'erin@hallym.ac.kr',
      attempts: 0,
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
      lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  const verifyCode = require('../api/verify-code');
  const res = mockRes();
  await verifyCode(
    mockReq({
      body: { code: '000000' },
      headers: { authorization: `Bearer ${idToken}` },
    }),
    res,
  );

  assert.equal(res.statusCode, 400);
  const after = await db.collection('emailVerificationCodes').doc(localId).get();
  assert.equal(after.data().attempts, 1);
});

test('verify-code: 만료된 코드는 410이고 문서가 삭제된다', async () => {
  const { idToken, localId } = await signUpTestUser('frank@hallym.ac.kr', 'password123');
  const db = admin.firestore();
  await db
    .collection('emailVerificationCodes')
    .doc(localId)
    .set({
      code: '111111',
      email: 'frank@hallym.ac.kr',
      attempts: 0,
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() - 1000),
      lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  const verifyCode = require('../api/verify-code');
  const res = mockRes();
  await verifyCode(
    mockReq({
      body: { code: '111111' },
      headers: { authorization: `Bearer ${idToken}` },
    }),
    res,
  );

  assert.equal(res.statusCode, 410);
  const after = await db.collection('emailVerificationCodes').doc(localId).get();
  assert.equal(after.exists, false);
});

test('verify-code: 5회 틀리면 잠기고(429) 문서가 삭제된다', async () => {
  const { idToken, localId } = await signUpTestUser('grace@hallym.ac.kr', 'password123');
  const db = admin.firestore();
  await db
    .collection('emailVerificationCodes')
    .doc(localId)
    .set({
      code: '222222',
      email: 'grace@hallym.ac.kr',
      attempts: 5,
      expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
      lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
    });

  const verifyCode = require('../api/verify-code');
  const res = mockRes();
  await verifyCode(
    mockReq({
      body: { code: '000000' },
      headers: { authorization: `Bearer ${idToken}` },
    }),
    res,
  );

  assert.equal(res.statusCode, 429);
  const after = await db.collection('emailVerificationCodes').doc(localId).get();
  assert.equal(after.exists, false);
});

test('비밀번호 재설정: 코드 발송 → 확인 → 재설정 전체 흐름이 성공한다', async () => {
  await signUpTestUser('henry@hallym.ac.kr', 'oldpassword1');

  const sendResetCode = require('../api/send-reset-code');
  const sendRes = mockRes();
  await sendResetCode(mockReq({ body: { email: 'henry@hallym.ac.kr' } }), sendRes);
  assert.equal(sendRes.statusCode, 200);
  assert.equal(sentEmails.length, 1);

  const db = admin.firestore();
  const userRecord = await admin.auth().getUserByEmail('henry@hallym.ac.kr');
  const codeDoc = await db.collection('passwordResetCodes').doc(userRecord.uid).get();
  const code = codeDoc.data().code;

  const verifyResetCode = require('../api/verify-reset-code');
  const verifyRes = mockRes();
  await verifyResetCode(
    mockReq({ body: { email: 'henry@hallym.ac.kr', code } }),
    verifyRes,
  );
  assert.equal(verifyRes.statusCode, 200);
  const resetToken = verifyRes._json.resetToken;
  assert.ok(resetToken);

  const resetPassword = require('../api/reset-password');
  const resetRes = mockRes();
  await resetPassword(
    mockReq({
      body: { email: 'henry@hallym.ac.kr', resetToken, newPassword: 'newpassword1' },
    }),
    resetRes,
  );
  assert.equal(resetRes.statusCode, 200);

  // 한 번 쓴 토큰은 재사용할 수 없어야 한다.
  const reuseRes = mockRes();
  await resetPassword(
    mockReq({
      body: {
        email: 'henry@hallym.ac.kr',
        resetToken,
        newPassword: 'anotherpassword',
      },
    }),
    reuseRes,
  );
  assert.equal(reuseRes.statusCode, 404);
});

test('send-reset-code: 가입되지 않은 이메일은 404', async () => {
  const sendResetCode = require('../api/send-reset-code');
  const res = mockRes();
  await sendResetCode(mockReq({ body: { email: 'nobody@hallym.ac.kr' } }), res);
  assert.equal(res.statusCode, 404);
  assert.equal(res._json.error, 'user-not-found');
});

test('send-reset-code: App Check 토큰이 없어도 APP_CHECK_ENFORCE가 꺼져 있으면 막지 않는다(기본값)', async () => {
  delete process.env.APP_CHECK_ENFORCE;
  const sendResetCode = require('../api/send-reset-code');
  const res = mockRes();
  // App Check 토큰 없이 호출 — user-not-found까지 도달한다면
  // App Check 단계에서 막히지 않았다는 뜻이다.
  await sendResetCode(mockReq({ body: { email: 'nobody@hallym.ac.kr' } }), res);
  assert.equal(res.statusCode, 404);
});

test('send-reset-code: APP_CHECK_ENFORCE=true인데 토큰이 없으면 401로 막는다', async () => {
  process.env.APP_CHECK_ENFORCE = 'true';
  try {
    const sendResetCode = require('../api/send-reset-code');
    const res = mockRes();
    await sendResetCode(mockReq({ body: { email: 'nobody@hallym.ac.kr' } }), res);
    assert.equal(res.statusCode, 401);
    assert.equal(res._json.error, 'app-check-failed');
  } finally {
    delete process.env.APP_CHECK_ENFORCE;
  }
});

test('reset-password: 잘못된 토큰이면 400', async () => {
  await signUpTestUser('iris@hallym.ac.kr', 'oldpassword1');
  const db = admin.firestore();
  const userRecord = await admin.auth().getUserByEmail('iris@hallym.ac.kr');
  await db
    .collection('passwordResetCodes')
    .doc(userRecord.uid)
    .set({
      resetToken: 'real-token',
      email: 'iris@hallym.ac.kr',
      resetTokenExpiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + 10 * 60 * 1000),
    });

  const resetPassword = require('../api/reset-password');
  const res = mockRes();
  await resetPassword(
    mockReq({
      body: {
        email: 'iris@hallym.ac.kr',
        resetToken: 'wrong-token',
        newPassword: 'newpassword1',
      },
    }),
    res,
  );
  assert.equal(res.statusCode, 400);
});

test('delete-my-reports: 본인이 남긴 신고만 지우고 다른 사람 신고는 남긴다', async () => {
  const { idToken, localId } = await signUpTestUser('ivan@hallym.ac.kr', 'password123');
  const db = admin.firestore();
  await db
    .collection('reports')
    .doc(`item1_${localId}`)
    .set({ itemId: 'item1', reporterUid: localId, reason: '스팸/광고' });
  await db
    .collection('reports')
    .doc('item2_other-uid')
    .set({ itemId: 'item2', reporterUid: 'other-uid', reason: '스팸/광고' });

  const deleteMyReports = require('../api/delete-my-reports');
  const res = mockRes();
  await deleteMyReports(
    mockReq({ headers: { authorization: `Bearer ${idToken}` } }),
    res,
  );

  assert.equal(res.statusCode, 200);
  assert.equal(res._json.deleted, 1);

  const mine = await db.collection('reports').doc(`item1_${localId}`).get();
  assert.equal(mine.exists, false);
  const others = await db.collection('reports').doc('item2_other-uid').get();
  assert.equal(others.exists, true);
});

test('cloudinary-signature: 로그인하지 않으면 401', async () => {
  const cloudinarySignature = require('../api/cloudinary-signature');
  const res = mockRes();
  await cloudinarySignature(mockReq({}), res);
  assert.equal(res.statusCode, 401);
});

test('cloudinary-signature: 환경변수가 없으면 500', async () => {
  delete process.env.CLOUDINARY_API_SECRET;
  const cloudinarySignature = require('../api/cloudinary-signature');
  const { idToken } = await signUpTestUser('judy@hallym.ac.kr', 'password123');
  const res = mockRes();
  await cloudinarySignature(
    mockReq({ headers: { authorization: `Bearer ${idToken}` } }),
    res,
  );
  assert.equal(res.statusCode, 500);
});

test('cloudinary-signature: 로그인한 사용자에게 검증 가능한 서명을 발급한다', async () => {
  process.env.CLOUDINARY_API_SECRET = 'test-secret';
  process.env.CLOUDINARY_API_KEY = 'test-key';
  process.env.CLOUDINARY_CLOUD_NAME = 'test-cloud';
  process.env.CLOUDINARY_UPLOAD_PRESET = 'test-preset';

  const cloudinarySignature = require('../api/cloudinary-signature');
  const { idToken } = await signUpTestUser('kate@hallym.ac.kr', 'password123');
  const res = mockRes();
  await cloudinarySignature(
    mockReq({ headers: { authorization: `Bearer ${idToken}` } }),
    res,
  );

  assert.equal(res.statusCode, 200);
  const { signature, timestamp, apiKey, cloudName, uploadPreset } = res._json;
  assert.equal(apiKey, 'test-key');
  assert.equal(cloudName, 'test-cloud');
  assert.equal(uploadPreset, 'test-preset');

  // 클라이언트가 실제로 검증받을 서명이므로, Cloudinary와 동일한 방식으로
  // 직접 재계산해 발급된 서명이 맞는지 확인한다.
  const expectedSignature = crypto
    .createHash('sha1')
    .update(`timestamp=${timestamp}&upload_preset=test-preset` + 'test-secret')
    .digest('hex');
  assert.equal(signature, expectedSignature);
});
