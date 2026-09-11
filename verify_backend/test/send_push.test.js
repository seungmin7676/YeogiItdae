const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  mockReq,
  mockRes,
  signUpTestUser: signUpUnverifiedTestUser,
  signUpVerifiedTestUser,
} = require('./helpers');

const AUTH_EMULATOR_HOST = '127.0.0.1:9099';
const FIRESTORE_EMULATOR_HOST = '127.0.0.1:8085';
const PROJECT_ID = 'demo-yeogi-itdae';
const ADMIN_EMAIL = 'admin1@hallym.ac.kr';

process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_EMULATOR_HOST;
process.env.FIRESTORE_EMULATOR_HOST = FIRESTORE_EMULATOR_HOST;
process.env.GCLOUD_PROJECT = PROJECT_ID;

let admin;
const sentPushes = [];

// send-push는 운영에서 이메일 인증을 마친 한림대 사용자만 호출할 수 있다.
async function signUpTestUser(email, password) {
  return signUpVerifiedTestUser(admin, email, password);
}

before((t) => {
  t.mock.module('../_push.js', {
    exports: {
      sendPushToUser: async (_admin, payload) => {
        sentPushes.push(payload);
        return { sent: 1, failed: 0 };
      },
    },
  });
  admin = require('../_admin');
});

beforeEach(async () => {
  sentPushes.length = 0;
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

function pushRequest(idToken, body) {
  return mockReq({
    headers: { authorization: `Bearer ${idToken}` },
    body,
  });
}

async function seedChatMessage({
  chatId,
  senderUid,
  recipientUid,
  text = '안녕하세요',
  messageId = 'message-1',
  createdAt = admin.firestore.Timestamp.now(),
}) {
  const db = admin.firestore();
  await db.collection('chats').doc(chatId).set({
    participants: [senderUid, recipientUid],
    participantNicknames: { [senderUid]: '앨리스', [recipientUid]: '밥' },
    lastMessage: text,
    lastMessageAt: admin.firestore.Timestamp.now(),
  });
  await db.collection('chats').doc(chatId).collection('messages').doc(messageId).set({
    senderUid,
    type: 'text',
    text,
    createdAt,
  });
  return messageId;
}

test('send-push: 인증 토큰이 없으면 401', async () => {
  const sendPush = require('../api/send-push');
  const res = mockRes();
  await sendPush(mockReq({ body: { type: 'chat_message' } }), res);
  assert.equal(res.statusCode, 401);
  assert.equal(sentPushes.length, 0);
});

test('send-push: 허용 목록에 없는 시스템 알림 종류를 거부한다', async () => {
  const sendPush = require('../api/send-push');
  const { idToken } = await signUpTestUser('alice@hallym.ac.kr', 'password123');
  const res = mockRes();
  await sendPush(
    pushRequest(idToken, {
      recipientUid: 'victim',
      type: 'password_changed',
      title: '시스템 알림',
      body: '비밀번호가 변경됐습니다',
    }),
    res,
  );
  assert.equal(res.statusCode, 400);
  assert.equal(res._json.error, 'unsupported-type');
  assert.equal(sentPushes.length, 0);
});

test('send-push: 실제 채팅 관계가 없는 임의 수신자에게 보낼 수 없다', async () => {
  const sendPush = require('../api/send-push');
  const { idToken, localId } = await signUpTestUser(
    'alice@hallym.ac.kr',
    'password123',
  );
  const res = mockRes();
  await sendPush(
    pushRequest(idToken, {
      recipientUid: 'victim',
      type: 'chat_message',
      title: '위조 제목',
      body: '위조 메시지',
      data: { chatId: `missing-${localId}`, messageId: 'message-1' },
    }),
    res,
  );
  assert.equal(res.statusCode, 403);
  assert.equal(res._json.error, 'event-not-authorized');
  assert.equal(sentPushes.length, 0);
});

test('send-push: 실제 본인 메시지는 채팅 상대에게 한 번만 보낼 수 있다', async () => {
  const sendPush = require('../api/send-push');
  const alice = await signUpTestUser('alice@hallym.ac.kr', 'password123');
  const bob = await signUpTestUser('bob@hallym.ac.kr', 'password123');
  await seedChatMessage({
    chatId: 'chat-1',
    senderUid: alice.localId,
    recipientUid: bob.localId,
    text: '검증된 메시지',
  });
  const request = pushRequest(alice.idToken, {
    recipientUid: bob.localId,
    type: 'chat_message',
    title: '시스템 관리자 사칭',
    body: '클라이언트가 조작한 본문',
    data: { chatId: 'chat-1', messageId: 'message-1', route: '/admin' },
  });

  const first = mockRes();
  await sendPush(request, first);
  assert.equal(first.statusCode, 200);
  assert.equal(sentPushes.length, 1);
  const delivery = await admin.firestore().collection('pushDeliveries').limit(1).get();
  assert.equal(delivery.size, 1);
  assert.ok(delivery.docs[0].data().expiresAt, '중복 방지 문서에 TTL이 있어야 한다');
  assert.deepEqual(sentPushes[0], {
    recipientUid: bob.localId,
    senderUid: alice.localId,
    type: 'chat_message',
    title: '앨리스',
    body: '검증된 메시지',
    data: { chatId: 'chat-1' },
  });

  const duplicate = mockRes();
  await sendPush(request, duplicate);
  assert.equal(duplicate.statusCode, 200);
  assert.equal(duplicate._json.skipped, 'duplicate');
  assert.equal(sentPushes.length, 1);
});

test('send-push: messageId가 없는 기존 앱 요청도 최신 본인 메시지면 허용한다', async () => {
  const sendPush = require('../api/send-push');
  const alice = await signUpTestUser('legacy-alice@hallym.ac.kr', 'password123');
  const bob = await signUpTestUser('legacy-bob@hallym.ac.kr', 'password123');
  await seedChatMessage({
    chatId: 'chat-legacy',
    senderUid: alice.localId,
    recipientUid: bob.localId,
  });

  const res = mockRes();
  await sendPush(
    pushRequest(alice.idToken, {
      recipientUid: bob.localId,
      type: 'chat_message',
      data: { chatId: 'chat-legacy' },
    }),
    res,
  );

  assert.equal(res.statusCode, 200);
  assert.equal(sentPushes.length, 1);
});

test('send-push: 상대가 보낸 메시지를 자기 이벤트처럼 재사용할 수 없다', async () => {
  const sendPush = require('../api/send-push');
  const alice = await signUpTestUser('alice@hallym.ac.kr', 'password123');
  const bob = await signUpTestUser('bob@hallym.ac.kr', 'password123');
  await seedChatMessage({
    chatId: 'chat-2',
    senderUid: bob.localId,
    recipientUid: alice.localId,
  });
  const res = mockRes();
  await sendPush(
    pushRequest(alice.idToken, {
      recipientUid: bob.localId,
      type: 'chat_message',
      data: { chatId: 'chat-2', messageId: 'message-1' },
    }),
    res,
  );
  assert.equal(res.statusCode, 403);
  assert.equal(sentPushes.length, 0);
});

test('send-push: 내 메시지 뒤에 답장이 먼저 와도 정확한 messageId로 발송한다', async () => {
  const sendPush = require('../api/send-push');
  const alice = await signUpTestUser('race-alice@hallym.ac.kr', 'password123');
  const bob = await signUpTestUser('race-bob@hallym.ac.kr', 'password123');
  await seedChatMessage({
    chatId: 'chat-race',
    senderUid: alice.localId,
    recipientUid: bob.localId,
    text: '먼저 보낸 메시지',
    messageId: 'alice-message',
  });
  const chatRef = admin.firestore().collection('chats').doc('chat-race');
  await chatRef.collection('messages').doc('bob-reply').set({
    senderUid: bob.localId,
    type: 'text',
    text: '빠른 답장',
    createdAt: admin.firestore.Timestamp.now(),
  });
  await chatRef.update({
    lastMessage: '빠른 답장',
    lastMessageAt: admin.firestore.Timestamp.now(),
  });

  const res = mockRes();
  await sendPush(
    pushRequest(alice.idToken, {
      recipientUid: bob.localId,
      type: 'chat_message',
      data: { chatId: 'chat-race', messageId: 'alice-message' },
    }),
    res,
  );

  assert.equal(res.statusCode, 200);
  assert.equal(sentPushes.length, 1);
  assert.equal(sentPushes[0].body, '먼저 보낸 메시지');
});

test('send-push: 오래된 메시지를 뒤늦게 재생해 푸시할 수 없다', async () => {
  const sendPush = require('../api/send-push');
  const alice = await signUpTestUser('old-alice@hallym.ac.kr', 'password123');
  const bob = await signUpTestUser('old-bob@hallym.ac.kr', 'password123');
  await seedChatMessage({
    chatId: 'chat-old',
    senderUid: alice.localId,
    recipientUid: bob.localId,
    messageId: 'old-message',
    createdAt: admin.firestore.Timestamp.fromMillis(Date.now() - 6 * 60 * 1000),
  });

  const res = mockRes();
  await sendPush(
    pushRequest(alice.idToken, {
      recipientUid: bob.localId,
      type: 'chat_message',
      data: { chatId: 'chat-old', messageId: 'old-message' },
    }),
    res,
  );
  assert.equal(res.statusCode, 403);
  assert.equal(sentPushes.length, 0);
});

test('send-push: 실제 본인 신고만 관리자에게 한 번 전달하고 본문을 서버에서 만든다', async () => {
  const sendPush = require('../api/send-push');
  await signUpVerifiedTestUser(admin, ADMIN_EMAIL, 'password123');
  const reporter = await signUpTestUser('reporter@hallym.ac.kr', 'password123');
  await admin.firestore().collection('reports').doc(`item-1_${reporter.localId}`).set({
    itemId: 'item-1',
    itemTitle: '검은 지갑',
    reporterUid: reporter.localId,
    reason: '부적절한 내용',
  });
  const request = pushRequest(reporter.idToken, {
    type: 'report_received',
    title: '관리자 사칭',
    body: '조작한 본문',
    data: { itemId: 'item-1', route: '/secret' },
  });

  const first = mockRes();
  await sendPush(request, first);
  assert.equal(first.statusCode, 200);
  assert.equal(sentPushes.length, 1);
  assert.equal(sentPushes[0].title, '새 신고 접수');
  assert.equal(sentPushes[0].body, "'검은 지갑' 게시글이 신고됐어요");
  assert.deepEqual(sentPushes[0].data, { itemId: 'item-1' });

  const duplicate = mockRes();
  await sendPush(request, duplicate);
  assert.equal(duplicate._json.skipped, 'duplicate');
  assert.equal(sentPushes.length, 1);
});

test('send-push: 일반 사용자는 관리자 신고 처리 알림을 발송할 수 없다', async () => {
  const sendPush = require('../api/send-push');
  const user = await signUpTestUser('alice@hallym.ac.kr', 'password123');
  const res = mockRes();
  await sendPush(
    pushRequest(user.idToken, {
      recipientUid: 'victim',
      type: 'item_removed',
      title: '신고 처리 안내',
      body: '게시글이 삭제됐습니다',
      data: { itemId: 'item-1' },
    }),
    res,
  );
  assert.equal(res.statusCode, 403);
  assert.equal(res._json.error, 'event-not-authorized');
  assert.equal(sentPushes.length, 0);
});
