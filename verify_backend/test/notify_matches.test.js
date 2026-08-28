// 키워드·카테고리 구독 알림(notify-matches)과 검색 토큰 백필 테스트.
//
// 예전에는 글을 올리는 클라이언트가 savedSearches 전체를 읽어 매칭했고, 그래서
// 보안 규칙이 남의 저장 키워드까지 열어줘야 했다. 이제 Admin SDK를 쓰는 이
// 엔드포인트가 매칭하므로, 여기서 그 동작이 맞는지 확인한다.
const { test, before, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const {
  mockReq,
  mockRes,
  signUpVerifiedTestUser,
} = require('./helpers');

const AUTH_EMULATOR_HOST = '127.0.0.1:9099';
const FIRESTORE_EMULATOR_HOST = '127.0.0.1:8085';
const PROJECT_ID = 'demo-yeogi-itdae';

process.env.FIREBASE_AUTH_EMULATOR_HOST = AUTH_EMULATOR_HOST;
process.env.FIRESTORE_EMULATOR_HOST = FIRESTORE_EMULATOR_HOST;
process.env.GCLOUD_PROJECT = PROJECT_ID;

// firestore.rules / lib/services/admin.dart 와 같은 값이어야 한다.
const ADMIN_EMAIL = '20225216@hallym.ac.kr';

let admin;
let buildSearchTokens;

before(() => {
  admin = require('../_admin');
  ({ buildSearchTokens } = require('../_search'));
});

beforeEach(async () => {
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

async function addItem(id, { authorUid, title, description = '', category = '기타', hidden = false }) {
  await admin.firestore().collection('items').doc(id).set({
    title,
    description,
    category,
    authorUid,
    authorNickname: '테스터',
    type: 'found',
    location: '(1) 공학관',
    locationDetail: '',
    resolved: false,
    imageUrls: [],
    hidden,
    searchTokens: buildSearchTokens(title, description),
    reportCount: 0,
    viewCount: 0,
  });
}

async function setSavedSearch(uid, { keywords = [], categories = [] }) {
  const keywordTokens = [
    ...new Set(keywords.map((keyword) => buildSearchTokens(keyword, '')[0]).filter(Boolean)),
  ];
  await admin.firestore().collection('savedSearches').doc(uid).set({
    keywords,
    keywordTokens,
    categories,
  });
}

async function notificationsFor(uid) {
  const snap = await admin
    .firestore()
    .collection('notifications')
    .where('recipientUid', '==', uid)
    .get();
  return snap.docs.map((d) => d.data());
}

// ---------------------------------------------------------------------------
// /api/notify-matches
// ---------------------------------------------------------------------------

test('notify-matches: 인증 토큰이 없으면 401', async () => {
  const notify = require('../api/notify-matches');
  const res = mockRes();
  await notify(mockReq({ body: { itemId: 'x' } }), res);
  assert.equal(res.statusCode, 401);
});

test('notify-matches: 없는 글이면 404', async () => {
  const notify = require('../api/notify-matches');
  const { idToken } = await signUpVerifiedTestUser(admin, 'poster@hallym.ac.kr', 'password123');
  const res = mockRes();
  await notify(
    mockReq({ body: { itemId: 'nope' }, headers: { authorization: `Bearer ${idToken}` } }),
    res,
  );
  assert.equal(res.statusCode, 404);
});

test('notify-matches: 남의 글을 빌미로 알림을 뿌릴 수 없다', async () => {
  const notify = require('../api/notify-matches');
  const { idToken } = await signUpVerifiedTestUser(admin, 'attacker@hallym.ac.kr', 'password123');
  await addItem('item1', { authorUid: 'someone-else', title: '검은색 지갑' });
  await setSavedSearch('victim', { keywords: ['지갑'] });

  const res = mockRes();
  await notify(
    mockReq({ body: { itemId: 'item1' }, headers: { authorization: `Bearer ${idToken}` } }),
    res,
  );

  assert.equal(res.statusCode, 403);
  assert.equal(res._json.error, 'not-author');
  assert.equal((await notificationsFor('victim')).length, 0);
});

test('notify-matches: 키워드가 일치하는 구독자에게 알림이 생성된다', async () => {
  const notify = require('../api/notify-matches');
  const { idToken, localId } = await signUpVerifiedTestUser(admin, 'poster2@hallym.ac.kr', 'password123');
  await addItem('item1', { authorUid: localId, title: '검은색 지갑 주웠어요' });
  await setSavedSearch('subscriber', { keywords: ['지갑'] });
  await setSavedSearch('unrelated', { keywords: ['우산'] });

  const res = mockRes();
  await notify(
    mockReq({ body: { itemId: 'item1' }, headers: { authorization: `Bearer ${idToken}` } }),
    res,
  );

  assert.equal(res.statusCode, 200);
  assert.equal(res._json.matched, 1);
  const got = await notificationsFor('subscriber');
  assert.equal(got.length, 1);
  assert.equal(got[0].type, 'keyword_match');
  assert.equal(got[0].matchType, 'keyword');
  assert.equal(got[0].keyword, '지갑');
  assert.equal(got[0].itemId, 'item1');
  assert.equal(got[0].read, false);
  assert.equal((await notificationsFor('unrelated')).length, 0);
});

test('notify-matches: 같은 글 요청을 재시도해도 알림은 한 번만 생성된다', async () => {
  const notify = require('../api/notify-matches');
  const { idToken, localId } = await signUpVerifiedTestUser(
    admin,
    'poster-idempotent@hallym.ac.kr',
    'password123',
  );
  await addItem('same-item', { authorUid: localId, title: '검은색 지갑' });
  await setSavedSearch('subscriber', { keywords: ['지갑'] });
  const request = mockReq({
    body: { itemId: 'same-item' },
    headers: { authorization: `Bearer ${idToken}` },
  });

  const first = mockRes();
  const second = mockRes();
  await notify(request, first);
  await notify(request, second);

  assert.equal(first._json.matched, 1);
  assert.equal(second._json.skipped, 'duplicate');
  assert.equal((await notificationsFor('subscriber')).length, 1);
});

test('notify-matches: 부분 포함과 띄어쓰기 차이도 매칭된다', async () => {
  const notify = require('../api/notify-matches');
  const { idToken, localId } = await signUpVerifiedTestUser(admin, 'poster3@hallym.ac.kr', 'password123');
  await addItem('item1', { authorUid: localId, title: '책가방과 아이폰 15' });
  await setSavedSearch('sub1', { keywords: ['가방'] }); // 부분 포함
  await setSavedSearch('sub2', { keywords: ['아이폰15'] }); // 띄어쓰기 다름

  await notify(
    mockReq({ body: { itemId: 'item1' }, headers: { authorization: `Bearer ${idToken}` } }),
    mockRes(),
  );

  assert.equal((await notificationsFor('sub1')).length, 1);
  assert.equal((await notificationsFor('sub2')).length, 1);
});

test('notify-matches: 카테고리 구독자에게도 알림이 간다', async () => {
  const notify = require('../api/notify-matches');
  const { idToken, localId } = await signUpVerifiedTestUser(admin, 'poster4@hallym.ac.kr', 'password123');
  await addItem('item1', { authorUid: localId, title: '노트북', category: '전자기기' });
  await setSavedSearch('sub', { categories: ['전자기기'] });

  await notify(
    mockReq({ body: { itemId: 'item1' }, headers: { authorization: `Bearer ${idToken}` } }),
    mockRes(),
  );

  const got = await notificationsFor('sub');
  assert.equal(got.length, 1);
  assert.equal(got[0].matchType, 'category');
  assert.equal(got[0].keyword, '전자기기');
});

test('notify-matches: 키워드와 카테고리가 둘 다 맞아도 알림은 한 번만(키워드 우선)', async () => {
  const notify = require('../api/notify-matches');
  const { idToken, localId } = await signUpVerifiedTestUser(admin, 'poster5@hallym.ac.kr', 'password123');
  await addItem('item1', { authorUid: localId, title: '노트북', category: '전자기기' });
  await setSavedSearch('sub', { keywords: ['노트북'], categories: ['전자기기'] });

  await notify(
    mockReq({ body: { itemId: 'item1' }, headers: { authorization: `Bearer ${idToken}` } }),
    mockRes(),
  );

  const got = await notificationsFor('sub');
  assert.equal(got.length, 1);
  assert.equal(got[0].matchType, 'keyword');
});

test('notify-matches: 글쓴이 본인에게는 보내지 않는다', async () => {
  const notify = require('../api/notify-matches');
  const { idToken, localId } = await signUpVerifiedTestUser(admin, 'poster6@hallym.ac.kr', 'password123');
  await addItem('item1', { authorUid: localId, title: '검은색 지갑' });
  await setSavedSearch(localId, { keywords: ['지갑'] });

  const res = mockRes();
  await notify(
    mockReq({ body: { itemId: 'item1' }, headers: { authorization: `Bearer ${idToken}` } }),
    res,
  );

  assert.equal(res._json.matched, 0);
  assert.equal((await notificationsFor(localId)).length, 0);
});

test('notify-matches: 숨김 처리된 글로는 알림을 보내지 않는다', async () => {
  const notify = require('../api/notify-matches');
  const { idToken, localId } = await signUpVerifiedTestUser(admin, 'poster7@hallym.ac.kr', 'password123');
  await addItem('item1', { authorUid: localId, title: '검은색 지갑', hidden: true });
  await setSavedSearch('sub', { keywords: ['지갑'] });

  const res = mockRes();
  await notify(
    mockReq({ body: { itemId: 'item1' }, headers: { authorization: `Bearer ${idToken}` } }),
    res,
  );

  assert.equal(res._json.skipped, 'hidden');
  assert.equal((await notificationsFor('sub')).length, 0);
});

// ---------------------------------------------------------------------------
// production API 밖에 보관한 일회성 검색 토큰 백필
// ---------------------------------------------------------------------------

test('backfill: 관리자가 아니면 403', async () => {
  const backfill = require('../maintenance/backfill-search-tokens');
  const { idToken } = await signUpVerifiedTestUser(
    admin,
    'notadmin@hallym.ac.kr',
    'password123',
  );
  const res = mockRes();
  await backfill(mockReq({ headers: { authorization: `Bearer ${idToken}` } }), res);
  assert.equal(res.statusCode, 403);
  assert.equal(res._json.error, 'admin-only');
});

test('backfill: 토큰이 없는 예전 글에만 채워 넣는다', async () => {
  const backfill = require('../maintenance/backfill-search-tokens');
  const { idToken } = await signUpVerifiedTestUser(admin, ADMIN_EMAIL, 'password123');
  const db = admin.firestore();

  // 검색 도입 전에 등록된 글(searchTokens 없음).
  await db.collection('items').doc('old').set({
    title: '검은색 지갑',
    description: '',
    authorUid: 'someone',
  });
  // 이미 채워진 글은 건드리지 않아야 한다.
  await db.collection('items').doc('new').set({
    title: '우산',
    description: '',
    authorUid: 'someone',
    searchTokens: ['이미'],
    hidden: false,
  });

  const res = mockRes();
  await backfill(mockReq({ headers: { authorization: `Bearer ${idToken}` } }), res);

  assert.equal(res.statusCode, 200);
  assert.equal(res._json.updated, 1);
  assert.equal(res._json.done, true);

  const old = await db.collection('items').doc('old').get();
  assert.deepEqual(old.data().searchTokens, buildSearchTokens('검은색 지갑', ''));
  assert.equal(old.data().hidden, false, '예전 글도 목록 쿼리에 노출되도록 백필');
  const fresh = await db.collection('items').doc('new').get();
  assert.deepEqual(fresh.data().searchTokens, ['이미'], '이미 채워진 글은 그대로');
});

test('backfill: 백필한 글이 앱과 같은 토큰으로 검색된다', async () => {
  const backfill = require('../maintenance/backfill-search-tokens');
  const { idToken } = await signUpVerifiedTestUser(admin, ADMIN_EMAIL, 'password123');
  const db = admin.firestore();
  await db.collection('items').doc('old').set({
    title: '학생회관에서 검은 지갑 주웠어요',
    description: '',
    authorUid: 'someone',
  });

  await backfill(mockReq({ headers: { authorization: `Bearer ${idToken}` } }), mockRes());

  // 앱이 '지갑'으로 검색할 때 쓰는 토큰('지갑')으로 실제 조회가 되는지.
  const found = await db
    .collection('items')
    .where('searchTokens', 'array-contains', '지갑')
    .get();
  assert.equal(found.size, 1);
  assert.equal(found.docs[0].id, 'old');
});

test('backfill: 두 번 돌려도 안전하다(멱등)', async () => {
  const backfill = require('../maintenance/backfill-search-tokens');
  const { idToken } = await signUpVerifiedTestUser(admin, ADMIN_EMAIL, 'password123');
  await admin.firestore().collection('items').doc('old').set({
    title: '지갑',
    description: '',
    authorUid: 'someone',
  });

  const first = mockRes();
  await backfill(mockReq({ headers: { authorization: `Bearer ${idToken}` } }), first);
  const second = mockRes();
  await backfill(mockReq({ headers: { authorization: `Bearer ${idToken}` } }), second);

  assert.equal(first._json.updated, 1);
  assert.equal(second._json.updated, 0, '두 번째 실행은 아무것도 바꾸지 않는다');
});

test('saved-search backfill: 기존 구독에 후보 조회 토큰을 채우며 멱등이다', async () => {
  const backfill = require('../maintenance/backfill-saved-search-tokens');
  const { idToken } = await signUpVerifiedTestUser(admin, ADMIN_EMAIL, 'password123');
  const ref = admin.firestore().collection('savedSearches').doc('legacy-user');
  await ref.set({ keywords: ['검은색 백팩', '지갑'], categories: [] });
  const request = mockReq({ headers: { authorization: `Bearer ${idToken}` } });

  const first = mockRes();
  const second = mockRes();
  await backfill(request, first);
  await backfill(request, second);

  assert.equal(first._json.updated, 1);
  assert.equal(second._json.updated, 0);
  assert.deepEqual((await ref.get()).data().keywordTokens, ['검은', '지갑']);
});
