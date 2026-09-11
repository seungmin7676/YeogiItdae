// firestore.rules 보안 규칙 테스트.
//
// 클라이언트 코드만 봐서는 "권한이 없어서 안 되는지" "버그라서 안 되는지"
// 구분하기 어렵고, 규칙 파일은 조건이 얽혀 있어(예: items 업데이트의
// "reportCount/viewCount는 정확히 +1만 허용") 별도 테스트 없이는 리팩터링
// 중 회귀를 알아차리기 어렵다. `npm test`로 실행한다(Firebase 에뮬레이터를
// 띄우고 끈다).
const { test, before, after, beforeEach } = require('node:test');
const assert = require('node:assert/strict');
const fs = require('node:fs');
const path = require('node:path');
const {
  initializeTestEnvironment,
  assertSucceeds,
  assertFails,
} = require('@firebase/rules-unit-testing');
const {
  doc,
  getDoc,
  setDoc,
  updateDoc,
  deleteDoc,
  addDoc,
  collection,
  getDocs,
  query,
  where,
  writeBatch,
  serverTimestamp,
} = require('firebase/firestore');

const PROJECT_ID = 'demo-yeogi-itdae';
const HALLYM_EMAIL = (id) => `${id}@hallym.ac.kr`;

let testEnv;

before(async () => {
  testEnv = await initializeTestEnvironment({
    projectId: PROJECT_ID,
    firestore: {
      rules: fs.readFileSync(path.resolve(__dirname, '../firestore.rules'), 'utf8'),
      host: '127.0.0.1',
      port: 8085,
    },
  });
});

after(async () => {
  await testEnv.cleanup();
});

beforeEach(async () => {
  await testEnv.clearFirestore();
});

/** 이메일 인증까지 마친 한림대 학생으로 로그인한 컨텍스트. */
function hallymUser(uid) {
  return testEnv.authenticatedContext(uid, {
    email: HALLYM_EMAIL(uid),
    email_verified: true,
  });
}

/** 이메일 인증을 아직 안 한 사용자. */
function unverifiedUser(uid) {
  return testEnv.authenticatedContext(uid, {
    email: HALLYM_EMAIL(uid),
    email_verified: false,
  });
}

/** 학교 계정이 아닌 일반 Firebase Auth 사용자. */
function externalUser(uid) {
  return testEnv.authenticatedContext(uid, {
    email: `${uid}@example.com`,
    email_verified: true,
  });
}

/** 관리자 계정(firestore.rules의 isAdmin 이메일과 일치). uid는 무관하다. */
function adminUser() {
  return testEnv.authenticatedContext('admin', {
    email: 'admin1@hallym.ac.kr',
    email_verified: true,
  });
}

const validItem = (authorUid, overrides = {}) => ({
  title: '검은색 백팩',
  description: '',
  location: '(1) 공학관',
  locationDetail: '',
  type: 'found',
  category: '가방',
  authorUid,
  authorNickname: '테스트유저',
  resolved: false,
  imageUrls: [],
  searchTokens: ['검은', '은색', '색백', '백팩'],
  reportCount: 0,
  viewCount: 0,
  hidden: false,
  createdAt: serverTimestamp(),
  ...overrides,
});

const validChatNotification = (chatId, overrides = {}) => ({
  recipientUid: 'bob',
  senderUid: 'alice',
  senderNickname: '앨리스',
  type: 'chat_started',
  itemId: 'item1',
  itemTitle: '검은색 백팩',
  chatId,
  read: false,
  createdAt: serverTimestamp(),
  ...overrides,
});

const validReport = (itemId, reporterUid, overrides = {}) => ({
  itemId,
  itemTitle: '검은색 백팩',
  authorUid: 'alice',
  authorNickname: '테스트유저',
  reporterUid,
  reason: '스팸/광고',
  createdAt: serverTimestamp(),
  ...overrides,
});

test('items: 이메일 인증까지 마친 한림대 사용자는 본인 명의로 글을 등록할 수 있다', async () => {
  const db = hallymUser('alice').firestore();
  await assertSucceeds(addDoc(collection(db, 'items'), validItem('alice')));
});

test('items: 이메일 인증을 안 한 사용자는 글을 등록할 수 없다', async () => {
  const db = unverifiedUser('alice').firestore();
  await assertFails(addDoc(collection(db, 'items'), validItem('alice')));
});

test('items: 한림대 도메인이 아닌 이메일은 글을 등록할 수 없다', async () => {
  const db = testEnv
    .authenticatedContext('alice', { email: 'alice@gmail.com', email_verified: true })
    .firestore();
  await assertFails(addDoc(collection(db, 'items'), validItem('alice')));
});

test('items: authorUid를 본인이 아닌 값으로 위조해 등록할 수 없다', async () => {
  const db = hallymUser('alice').firestore();
  await assertFails(addDoc(collection(db, 'items'), validItem('bob')));
});

test('items: resolved 같은 필드 타입이 틀리면 등록이 거부된다', async () => {
  const db = hallymUser('alice').firestore();
  await assertFails(
    addDoc(collection(db, 'items'), validItem('alice', { resolved: 'false' })),
  );
});

test('items: 작성자 본인은 허용된 글 필드를 수정할 수 있다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('alice').firestore();
  await assertSucceeds(updateDoc(doc(db, 'items', itemId), { title: '수정된 제목' }));
});

test('items: 작성자도 hidden·카운터·createdAt·임의 필드를 조작할 수 없다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('alice').firestore();
  await assertFails(updateDoc(doc(db, 'items', itemId), { hidden: true }));
  await assertFails(updateDoc(doc(db, 'items', itemId), { reportCount: 5 }));
  await assertFails(updateDoc(doc(db, 'items', itemId), { viewCount: 999 }));
  await assertFails(updateDoc(doc(db, 'items', itemId), { createdAt: new Date(0) }));
  await assertFails(updateDoc(doc(db, 'items', itemId), { isAdmin: true }));
});

test('items: 생성 시 서버 제어 필드와 필드 길이를 위조할 수 없다', async () => {
  const db = hallymUser('alice').firestore();
  await assertFails(
    addDoc(collection(db, 'items'), validItem('alice', { hidden: true })),
  );
  await assertFails(
    addDoc(collection(db, 'items'), validItem('alice', { reportCount: 99 })),
  );
  await assertFails(
    addDoc(collection(db, 'items'), validItem('alice', { title: '가'.repeat(41) })),
  );
});

test('items: 작성자는 글을 거래완료로 표시할 수 있다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('alice').firestore();
  await assertSucceeds(updateDoc(doc(db, 'items', itemId), { resolved: true }));
});

test('items: 이미 완료된 글을 다시 완료 처리해도 안전한 no-op으로 허용된다(멱등성)', async () => {
  const itemId = await seedItem('alice', { resolved: true });
  const db = hallymUser('alice').firestore();
  await assertSucceeds(updateDoc(doc(db, 'items', itemId), { resolved: true }));
});

test('items: 일부 필드가 없는 legacy 문서도 작성자가 거래완료 처리할 수 있다', async () => {
  // 예전 버전 앱이 등록한 문서: locationDetail/category/imageUrls가 없고
  // imageUrl(단수)만 있다. 과거 규칙은 수정 시 전체 필드 존재를 요구해
  // 이런 문서가 일괄 처리 batch에 끼면 전체가 실패했다.
  let itemId;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const ref = await addDoc(collection(ctx.firestore(), 'items'), {
      title: '옛날 글',
      location: '(1) 공학관',
      type: 'found',
      authorUid: 'alice',
      authorNickname: '테스트유저',
      resolved: false,
      imageUrl: 'https://example.com/old.png',
    });
    itemId = ref.id;
  });
  const db = hallymUser('alice').firestore();
  await assertSucceeds(updateDoc(doc(db, 'items', itemId), { resolved: true }));
});

test('items: 수정 시에도 resolved에 bool이 아닌 값은 거부된다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('alice').firestore();
  await assertFails(updateDoc(doc(db, 'items', itemId), { resolved: 'true' }));
});

test('items: 이미 삭제된 글의 거래완료 처리는 거부된다(중복 실행 방어)', async () => {
  const db = hallymUser('alice').firestore();
  await assertFails(
    updateDoc(doc(db, 'items', 'nonexistent-item'), { resolved: true }),
  );
});

test('items: 신고 문서 없이 reportCount만 +1 할 수 없다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('bob').firestore();
  await assertFails(updateDoc(doc(db, 'items', itemId), { reportCount: 1 }));
});

test('items: 작성자가 아닌 사용자는 reportCount를 2 이상 건너뛰어 조작할 수 없다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('bob').firestore();
  await assertFails(updateDoc(doc(db, 'items', itemId), { reportCount: 5 }));
});

test('items: 작성자가 아닌 사용자는 title 등 다른 필드를 수정할 수 없다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('bob').firestore();
  await assertFails(updateDoc(doc(db, 'items', itemId), { title: '남의 글 수정' }));
});

test('items: 원본 미디어 정리를 우회하지 못하도록 클라이언트 직접 삭제를 막는다', async () => {
  const itemId = await seedItem('alice');
  const other = hallymUser('bob').firestore();
  await assertFails(deleteDoc(doc(other, 'items', itemId)));

  const owner = hallymUser('alice').firestore();
  await assertFails(deleteDoc(doc(owner, 'items', itemId)));
});

test('items: 읽기는 이메일 인증된 한림대 사용자에게만 허용된다', async () => {
  const itemId = await seedItem('alice');
  const anonymous = testEnv.unauthenticatedContext().firestore();
  await assertFails(getDoc(doc(anonymous, 'items', itemId)));
  await assertFails(getDoc(doc(unverifiedUser('bob').firestore(), 'items', itemId)));
  await assertFails(getDoc(doc(externalUser('bob').firestore(), 'items', itemId)));
  await assertSucceeds(getDoc(doc(hallymUser('bob').firestore(), 'items', itemId)));
});

test('items: 숨김 글은 작성자·관리자만 단건 조회하고 일반 목록은 hidden=false를 증명해야 한다', async () => {
  const visibleId = await seedItem('alice');
  const hiddenId = await seedItem('alice', { hidden: true });
  const bob = hallymUser('bob').firestore();
  await assertFails(getDoc(doc(bob, 'items', hiddenId)));
  await assertSucceeds(getDoc(doc(hallymUser('alice').firestore(), 'items', hiddenId)));
  await assertSucceeds(getDoc(doc(adminUser().firestore(), 'items', hiddenId)));
  await assertFails(getDocs(collection(bob, 'items')));
  const snap = await assertSucceeds(
    getDocs(query(collection(bob, 'items'), where('hidden', '==', false))),
  );
  assert.deepEqual(snap.docs.map((entry) => entry.id), [visibleId]);
});

test('reports: 본인 명의로만, 그리고 문서ID가 itemId_uid 형식이어야 신고할 수 있다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('bob').firestore();
  const batch = writeBatch(db);
  batch.set(doc(db, 'reports', `${itemId}_bob`), validReport(itemId, 'bob'));
  batch.update(doc(db, 'items', itemId), { reportCount: 1 });
  await assertSucceeds(batch.commit());
});

test('reports: 문서ID가 본인 uid와 일치하지 않으면 신고할 수 없다(중복 신고 방지 우회 차단)', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('bob').firestore();
  const batch = writeBatch(db);
  batch.set(
    doc(db, 'reports', `${itemId}_carol`),
    validReport(itemId, 'bob'),
  );
  batch.update(doc(db, 'items', itemId), { reportCount: 1 });
  await assertFails(batch.commit());
});

test('reports: 관리자 화면에 표시할 상품 정보를 위조할 수 없다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('bob').firestore();
  const batch = writeBatch(db);
  batch.set(
    doc(db, 'reports', `${itemId}_bob`),
    validReport(itemId, 'bob', { itemTitle: '위조된 제목' }),
  );
  batch.update(doc(db, 'items', itemId), { reportCount: 1 });
  await assertFails(batch.commit());
});

test('reports: 자기 게시글을 직접 신고할 수 없다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('alice').firestore();
  const batch = writeBatch(db);
  batch.set(
    doc(db, 'reports', `${itemId}_alice`),
    validReport(itemId, 'alice'),
  );
  batch.update(doc(db, 'items', itemId), { reportCount: 1 });
  await assertFails(batch.commit());
});

test('reports: 같은 사용자의 중복 batch는 신고 수를 다시 올릴 수 없다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('bob').firestore();
  const first = writeBatch(db);
  first.set(doc(db, 'reports', `${itemId}_bob`), validReport(itemId, 'bob'));
  first.update(doc(db, 'items', itemId), { reportCount: 1 });
  await assertSucceeds(first.commit());

  const duplicate = writeBatch(db);
  duplicate.set(
    doc(db, 'reports', `${itemId}_bob`),
    validReport(itemId, 'bob'),
  );
  duplicate.update(doc(db, 'items', itemId), { reportCount: 2 });
  await assertFails(duplicate.commit());

  const item = await getDoc(doc(db, 'items', itemId));
  assert.equal(item.data().reportCount, 1);
});

test('reports: 신고 문서는 본인 것이라도 클라이언트에서 읽을 수 없다', async () => {
  const itemId = await seedItem('alice');
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'reports', `${itemId}_bob`), {
      itemId,
      reporterUid: 'bob',
      reason: '스팸/광고',
    });
  });
  const db = hallymUser('bob').firestore();
  await assertFails(getDoc(doc(db, 'reports', `${itemId}_bob`)));
});

test('userPrivate: 본인만 실명 등 개인정보 문서를 읽고 생성할 수 있다', async () => {
  const db = testEnv.authenticatedContext('alice', {
    email: '20240001@hallym.ac.kr',
    email_verified: false,
  }).firestore();
  await assertSucceeds(
    setDoc(doc(db, 'userPrivate', 'alice'), {
      nickname: '테스트',
      realName: '홍길동',
      department: '컴퓨터공학과',
      studentId: '20240001',
    }),
  );
  await assertSucceeds(getDoc(doc(db, 'userPrivate', 'alice')));

  const other = hallymUser('bob').firestore();
  await assertFails(getDoc(doc(other, 'userPrivate', 'alice')));
});

test('userPrivate: 위변조 방지를 위해 본인이라도 수정은 불가능하다', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'userPrivate', 'alice'), {
      nickname: '테스트',
      realName: '홍길동',
      department: '컴퓨터공학과',
      studentId: 'alice',
    });
  });
  const db = hallymUser('alice').firestore();
  await assertFails(updateDoc(doc(db, 'userPrivate', 'alice'), { realName: '변조된이름' }));
});

test('userPublicProfiles: 로그인한 사용자라면 누구나 다른 사람 프로필을 읽을 수 있다', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'userPublicProfiles', 'alice'), { nickname: '앨리스' });
  });
  const db = hallymUser('bob').firestore();
  await assertSucceeds(getDoc(doc(db, 'userPublicProfiles', 'alice')));
});

test('userPublicProfiles: 미인증·외부 계정은 다른 사람 프로필을 읽을 수 없다', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'userPublicProfiles', 'alice'), { nickname: '앨리스' });
  });
  await assertFails(getDoc(doc(unverifiedUser('bob').firestore(), 'userPublicProfiles', 'alice')));
  await assertFails(getDoc(doc(externalUser('bob').firestore(), 'userPublicProfiles', 'alice')));
});

test('userPublicProfiles: 본인 프로필도 nickname/photoUrl 외 필드는 쓸 수 없다', async () => {
  const db = hallymUser('alice').firestore();
  await assertFails(
    setDoc(doc(db, 'userPublicProfiles', 'alice'), {
      nickname: '앨리스',
      isAdmin: true,
    }),
  );
});

test('userPublicProfiles: 다른 사람의 프로필은 쓸 수 없다', async () => {
  const db = hallymUser('bob').firestore();
  await assertFails(setDoc(doc(db, 'userPublicProfiles', 'alice'), { nickname: '해킹시도' }));
});

test('chats: 참여자 2명이 아니면 채팅방을 만들 수 없다', async () => {
  const itemId = await seedItem('bob');
  const db = hallymUser('alice').firestore();
  await assertFails(
    setDoc(doc(db, 'chats', `${itemId}_alice_bob`), {
      participants: ['alice'],
      itemId,
      itemAuthorUid: 'bob',
      itemTitle: '검은색 백팩',
      resolutionStatus: 'none',
    }),
  );
});

test('chats: 본인이 참여자에 포함되어야 채팅방을 만들 수 있다', async () => {
  const itemId = await seedItem('bob');
  const db = hallymUser('alice').firestore();
  await assertSucceeds(
    setDoc(doc(db, 'chats', `${itemId}_alice_bob`), {
      participants: ['alice', 'bob'],
      itemId,
      itemAuthorUid: 'bob',
      itemTitle: '검은색 백팩',
      resolutionStatus: 'none',
    }),
  );
});

test('chats: 미인증·외부 Firebase 계정은 학교 인증 없이 채팅을 만들 수 없다', async () => {
  const itemId = await seedItem('bob');
  const payload = {
    participants: ['alice', 'bob'],
    itemId,
    itemAuthorUid: 'bob',
    itemTitle: '검은색 백팩',
    resolutionStatus: 'none',
  };
  await assertFails(
    setDoc(doc(unverifiedUser('alice').firestore(), 'chats', `${itemId}_alice_bob`), payload),
  );
  await assertFails(
    setDoc(doc(externalUser('alice').firestore(), 'chats', `${itemId}_alice_bob`), payload),
  );
});

test('chats: 어느 한쪽이 상대를 차단했으면 새 채팅을 만들 수 없다', async () => {
  const itemId = await seedItem('bob');
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'blocks', 'bob'), {
      blockedUsers: { alice: '앨리스' },
    });
  });
  const db = hallymUser('alice').firestore();
  await assertFails(
    setDoc(doc(db, 'chats', `${itemId}_alice_bob`), {
      participants: ['alice', 'bob'],
      itemId,
      itemAuthorUid: 'bob',
      itemTitle: '검은색 백팩',
      resolutionStatus: 'none',
    }),
  );
});

test('chats: 실제 게시글 작성자가 아닌 임의 사용자를 상대로 채팅방을 만들 수 없다', async () => {
  const itemId = await seedItem('bob');
  const db = hallymUser('alice').firestore();
  await assertFails(
    setDoc(doc(db, 'chats', `${itemId}_alice_carol`), {
      participants: ['alice', 'carol'],
      itemId,
      itemAuthorUid: 'carol',
      itemTitle: '검은색 백팩',
      resolutionStatus: 'none',
    }),
  );
});

test('chats: 같은 글·참여자로 임의 chatId를 사용해 채팅방을 복제할 수 없다', async () => {
  const itemId = await seedItem('bob');
  const db = hallymUser('alice').firestore();
  await assertFails(
    setDoc(doc(db, 'chats', 'attacker-selected-id'), {
      participants: ['alice', 'bob'],
      itemId,
      itemAuthorUid: 'bob',
      itemTitle: '검은색 백팩',
      resolutionStatus: 'none',
    }),
  );
});

test('chats: 참여자는 lastMessage 같은 진행 필드를 수정할 수 있다', async () => {
  const chatId = await seedChat('alice', 'bob');
  const db = hallymUser('alice').firestore();
  await assertSucceeds(updateDoc(doc(db, 'chats', chatId), { lastMessage: '안녕하세요' }));
});

test('chats: 실제 메시지 전송 메타데이터 묶음은 기존 동작대로 허용된다', async () => {
  const chatId = await seedChat('alice', 'bob', {
    unreadCount: { bob: 2 },
    typing: { alice: true },
  });
  const db = hallymUser('alice').firestore();
  await assertSucceeds(
    updateDoc(doc(db, 'chats', chatId), {
      lastMessage: '새 메시지',
      lastMessageAt: new Date(),
      'lastReadAt.alice': new Date(),
      'unreadCount.bob': 3,
      'typing.alice': false,
    }),
  );
});

test('chats: 상대방의 실명 공개 값을 대신 만들거나 바꿀 수 없다', async () => {
  const chatId = await seedChat('alice', 'bob', {
    revealedRealNames: { bob: '홍길동 (20240001)' },
  });
  const db = hallymUser('alice').firestore();
  await assertFails(
    updateDoc(doc(db, 'chats', chatId), {
      'revealedRealNames.bob': '위조된 실명 (00000000)',
    }),
  );
  await assertSucceeds(
    updateDoc(doc(db, 'chats', chatId), {
      'revealedRealNames.alice': '앨리스 (20240002)',
    }),
  );
});

test('chats: 상대방의 닉네임·입력 중·읽음 시각을 대신 조작할 수 없다', async () => {
  const chatId = await seedChat('alice', 'bob', {
    participantNicknames: { alice: '앨리스', bob: '밥' },
    typing: { bob: false },
    lastReadAt: { bob: new Date(0) },
  });
  const db = hallymUser('alice').firestore();
  await assertFails(
    updateDoc(doc(db, 'chats', chatId), { 'participantNicknames.bob': '관리자' }),
  );
  await assertFails(updateDoc(doc(db, 'chats', chatId), { 'typing.bob': true }));
  await assertFails(
    updateDoc(doc(db, 'chats', chatId), { 'lastReadAt.bob': new Date() }),
  );
  await assertSucceeds(
    updateDoc(doc(db, 'chats', chatId), {
      'participantNicknames.alice': '새 앨리스',
      'typing.alice': true,
      'lastReadAt.alice': new Date(),
    }),
  );
});

test('chats: 상대방의 안읽음 수를 지울 수 없고 본인 것만 0으로 만들 수 있다', async () => {
  const chatId = await seedChat('alice', 'bob', {
    unreadCount: { alice: 3, bob: 2 },
  });
  const db = hallymUser('alice').firestore();
  await assertFails(updateDoc(doc(db, 'chats', chatId), { 'unreadCount.bob': 0 }));
  await assertSucceeds(updateDoc(doc(db, 'chats', chatId), { 'unreadCount.alice': 0 }));
});

test('chats: 게시글 작성자만 거래완료를 요청하고 상대만 확인할 수 있다', async () => {
  const chatId = await seedChat('alice', 'bob', { resolutionStatus: 'none' });
  const alice = hallymUser('alice').firestore();
  const bob = hallymUser('bob').firestore();

  await assertFails(
    updateDoc(doc(alice, 'chats', chatId), { resolutionStatus: 'pending' }),
  );
  await assertSucceeds(
    updateDoc(doc(bob, 'chats', chatId), { resolutionStatus: 'pending' }),
  );
  await assertFails(
    updateDoc(doc(bob, 'chats', chatId), { resolutionStatus: 'confirmed' }),
  );
  await assertSucceeds(
    updateDoc(doc(alice, 'chats', chatId), { resolutionStatus: 'confirmed' }),
  );
});

test('chats: 게시글 작성자만 삭제 상태를 표시할 수 있고 되돌릴 수 없다', async () => {
  const chatId = await seedChat('alice', 'bob');
  const alice = hallymUser('alice').firestore();
  const bob = hallymUser('bob').firestore();
  await assertFails(updateDoc(doc(alice, 'chats', chatId), { itemDeleted: true }));
  await assertSucceeds(updateDoc(doc(bob, 'chats', chatId), { itemDeleted: true }));
  await assertFails(updateDoc(doc(bob, 'chats', chatId), { itemDeleted: false }));
});

test('chats: 참여자라도 participants 같은 고정 필드는 수정할 수 없다', async () => {
  const chatId = await seedChat('alice', 'bob');
  const db = hallymUser('alice').firestore();
  await assertFails(
    updateDoc(doc(db, 'chats', chatId), { participants: ['alice', 'carol'] }),
  );
});

test('chats: 참가자 한 명이 공유 채팅방 전체를 삭제할 수 없다', async () => {
  const chatId = await seedChat('alice', 'bob');
  const db = hallymUser('alice').firestore();
  await assertFails(deleteDoc(doc(db, 'chats', chatId)));
});

test('chats: itemId만으로 거는 목록 쿼리는 참여자여도 거부된다(list 규칙 증명 불가)', async () => {
  // 게시글 삭제/거래완료 시 관련 채팅방을 정리하는 클라이언트 쿼리의 회귀
  // 테스트. participants 필터가 없으면 규칙이 "결과가 전부 본인 채팅"임을
  // 증명할 수 없어 데이터와 무관하게 쿼리 전체가 거부된다.
  await seedChat('alice', 'bob');
  const db = hallymUser('bob').firestore();
  await assertFails(
    getDocs(query(collection(db, 'chats'), where('itemId', '==', 'item1'))),
  );
});

test('chats: participants 필터를 함께 걸면 itemId 목록 쿼리가 허용된다', async () => {
  await seedChat('alice', 'bob');
  const db = hallymUser('bob').firestore();
  const snap = await assertSucceeds(
    getDocs(
      query(
        collection(db, 'chats'),
        where('participants', 'array-contains', 'bob'),
        where('itemId', '==', 'item1'),
      ),
    ),
  );
  assert.equal(snap.docs.length, 1);
});

test('chats: 참여자가 아니면 채팅방을 조회할 수 없다', async () => {
  const chatId = await seedChat('alice', 'bob');
  const db = hallymUser('carol').firestore();
  await assertFails(getDoc(doc(db, 'chats', chatId)));
});

test('chats/messages: 참여자는 본인 명의로 메시지를 보낼 수 있다', async () => {
  const chatId = await seedChat('alice', 'bob');
  const db = hallymUser('alice').firestore();
  await assertSucceeds(
    addDoc(collection(db, 'chats', chatId, 'messages'), {
      senderUid: 'alice',
      type: 'text',
      text: '안녕!',
      createdAt: serverTimestamp(),
    }),
  );
});

test('chats/messages: 차단 이후에는 새 메시지와 lastMessage 갱신이 서버에서 거부된다', async () => {
  const chatId = await seedChat('alice', 'bob');
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'blocks', 'bob'), {
      blockedUsers: { alice: '앨리스' },
    });
  });
  const db = hallymUser('alice').firestore();
  await assertFails(
    addDoc(collection(db, 'chats', chatId, 'messages'), {
      senderUid: 'alice',
      type: 'text',
      text: '차단 뒤 메시지',
      createdAt: serverTimestamp(),
    }),
  );
  await assertFails(
    updateDoc(doc(db, 'chats', chatId), {
      lastMessage: '차단 뒤 메시지',
      lastMessageAt: new Date(),
    }),
  );
});

test('chats/messages: 발신자를 상대방으로 위조해 보낼 수 없다', async () => {
  const chatId = await seedChat('alice', 'bob');
  const db = hallymUser('alice').firestore();
  await assertFails(
    addDoc(collection(db, 'chats', chatId, 'messages'), {
      senderUid: 'bob',
      type: 'text',
      text: '위조된 메시지',
      createdAt: serverTimestamp(),
    }),
  );
});

test('chats/messages: 알 수 없는 타입·과대 텍스트·추가 필드를 거부한다', async () => {
  const chatId = await seedChat('alice', 'bob');
  const db = hallymUser('alice').firestore();
  const messages = collection(db, 'chats', chatId, 'messages');

  await assertFails(
    addDoc(messages, {
      senderUid: 'alice',
      type: 'system',
      text: '관리자 메시지',
      createdAt: serverTimestamp(),
    }),
  );
  await assertFails(
    addDoc(messages, {
      senderUid: 'alice',
      type: 'text',
      text: '가'.repeat(2001),
      createdAt: serverTimestamp(),
    }),
  );
  await assertFails(
    addDoc(messages, {
      senderUid: 'alice',
      type: 'text',
      text: '정상처럼 보이는 메시지',
      isAdmin: true,
      createdAt: serverTimestamp(),
    }),
  );
});

test('chats/messages: Cloudinary HTTPS 이미지만 서버 시각과 함께 저장할 수 있다', async () => {
  const chatId = await seedChat('alice', 'bob');
  const db = hallymUser('alice').firestore();
  const messages = collection(db, 'chats', chatId, 'messages');

  await assertSucceeds(
    addDoc(messages, {
      senderUid: 'alice',
      type: 'image',
      imageUrl: 'https://res.cloudinary.com/demo/image/upload/sample.jpg',
      createdAt: serverTimestamp(),
    }),
  );
  await assertFails(
    addDoc(messages, {
      senderUid: 'alice',
      type: 'image',
      imageUrl: 'http://attacker.example/image.jpg',
      createdAt: serverTimestamp(),
    }),
  );
  await assertFails(
    addDoc(messages, {
      senderUid: 'alice',
      type: 'text',
      text: '조작된 시각',
      createdAt: new Date(0),
    }),
  );
});

test('chats/messages: 참여자가 아니면 메시지를 읽을 수 없다', async () => {
  const chatId = await seedChat('alice', 'bob');
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await addDoc(collection(ctx.firestore(), 'chats', chatId, 'messages'), {
      senderUid: 'alice',
      type: 'text',
      text: '안녕!',
    });
  });
  const db = hallymUser('carol').firestore();
  await assertFails(getDoc(doc(db, 'chats', chatId, 'messages', 'nonexistent')));
});

test('chats/messages: 참가자는 자기 또는 상대 메시지를 삭제할 수 없다', async () => {
  const chatId = await seedChat('alice', 'bob');
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const db = ctx.firestore();
    await setDoc(doc(db, 'chats', chatId, 'messages', 'from-alice'), {
      senderUid: 'alice',
      type: 'text',
      text: '내 메시지',
    });
    await setDoc(doc(db, 'chats', chatId, 'messages', 'from-bob'), {
      senderUid: 'bob',
      type: 'text',
      text: '상대 메시지',
    });
  });

  const db = hallymUser('alice').firestore();
  await assertFails(
    deleteDoc(doc(db, 'chats', chatId, 'messages', 'from-alice')),
  );
  await assertFails(
    deleteDoc(doc(db, 'chats', chatId, 'messages', 'from-bob')),
  );
});

test('notifications: 실제 채팅 참여자는 상대 참여자에게 채팅 시작 알림을 생성할 수 있다', async () => {
  const chatId = await seedChat('alice', 'bob');
  const db = hallymUser('alice').firestore();
  await assertSucceeds(
    addDoc(collection(db, 'notifications'), validChatNotification(chatId)),
  );
});

test('notifications: 채팅 관계가 없는 임의 사용자에게 채팅 시작 알림을 만들 수 없다', async () => {
  const chatId = await seedChat('alice', 'bob');
  const db = hallymUser('alice').firestore();
  await assertFails(
    addDoc(
      collection(db, 'notifications'),
      validChatNotification(chatId, { recipientUid: 'carol' }),
    ),
  );
});

test('notifications: 존재하지 않는 채팅을 근거로 채팅 시작 알림을 만들 수 없다', async () => {
  const db = hallymUser('alice').firestore();
  await assertFails(
    addDoc(
      collection(db, 'notifications'),
      validChatNotification('missing-chat'),
    ),
  );
});

test('notifications: 수신자 본인만 알림을 읽을 수 있다', async () => {
  let notifId;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const ref = await addDoc(collection(ctx.firestore(), 'notifications'), {
      recipientUid: 'bob',
      senderUid: 'alice',
      type: 'chat_started',
      read: false,
    });
    notifId = ref.id;
  });

  const recipient = hallymUser('bob').firestore();
  await assertSucceeds(getDoc(doc(recipient, 'notifications', notifId)));

  const stranger = hallymUser('carol').firestore();
  await assertFails(getDoc(doc(stranger, 'notifications', notifId)));
});

test('notifications: 수신자는 read만 true로 바꿀 수 있고 수신자·종류는 위조할 수 없다', async () => {
  let notifId;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const ref = await addDoc(collection(ctx.firestore(), 'notifications'), {
      recipientUid: 'bob',
      senderUid: 'alice',
      type: 'chat_started',
      read: false,
    });
    notifId = ref.id;
  });
  const db = hallymUser('bob').firestore();
  await assertSucceeds(updateDoc(doc(db, 'notifications', notifId), { read: true }));
  await assertFails(updateDoc(doc(db, 'notifications', notifId), { recipientUid: 'carol' }));
  await assertFails(updateDoc(doc(db, 'notifications', notifId), { type: 'item_removed' }));
  await assertFails(updateDoc(doc(db, 'notifications', notifId), { read: false }));
});

test('reportAppeals: 숨김 처리된 본인 글의 작성자는 이의제기를 등록할 수 있다', async () => {
  const itemId = await seedItem('alice', { reportCount: 3 });
  const db = hallymUser('alice').firestore();
  await assertSucceeds(
    setDoc(doc(db, 'reportAppeals', itemId), {
      itemId,
      itemTitle: '검은색 백팩',
      authorUid: 'alice',
      reason: '오해로 신고당했어요',
      status: 'pending',
      createdAt: serverTimestamp(),
    }),
  );
});

test('reportAppeals: 다른 사람의 글에 대해 본인 명의로 이의제기를 등록할 수 없다', async () => {
  const itemId = await seedItem('alice', { reportCount: 3 });
  const db = hallymUser('bob').firestore();
  await assertFails(
    setDoc(doc(db, 'reportAppeals', itemId), {
      itemId,
      itemTitle: '검은색 백팩',
      authorUid: 'bob',
      reason: '내가 신고했지만 이의제기해봄',
      status: 'pending',
      createdAt: serverTimestamp(),
    }),
  );
});

test('reportAppeals: 본인 이의제기는 읽을 수 있지만 남의 것은 읽을 수 없다', async () => {
  const itemId = await seedItem('alice', { reportCount: 3 });
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'reportAppeals', itemId), {
      itemId,
      itemTitle: '검은색 백팩',
      authorUid: 'alice',
      reason: '오해로 신고당했어요',
      status: 'pending',
    });
  });

  const owner = hallymUser('alice').firestore();
  await assertSucceeds(getDoc(doc(owner, 'reportAppeals', itemId)));

  const stranger = hallymUser('bob').firestore();
  await assertFails(getDoc(doc(stranger, 'reportAppeals', itemId)));
});

test('items: 관리자는 어떤 글이든 hidden으로 숨길 수 있다', async () => {
  const itemId = await seedItem('alice');
  const db = adminUser().firestore();
  await assertSucceeds(updateDoc(doc(db, 'items', itemId), { hidden: true }));
});

test('items: 일반 사용자는 hidden 필드를 조작할 수 없다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('bob').firestore();
  await assertFails(updateDoc(doc(db, 'items', itemId), { hidden: true }));
});

test('items: 작성자 본인도 관리자 hidden 조치를 해제할 수 없다', async () => {
  const itemId = await seedItem('alice', { hidden: true });
  const db = hallymUser('alice').firestore();
  await assertFails(updateDoc(doc(db, 'items', itemId), { hidden: false }));
});

test('items: 관리자는 신고 반려로 reportCount를 0으로 초기화할 수 있다', async () => {
  const itemId = await seedItem('alice', { reportCount: 5 });
  const db = adminUser().firestore();
  await assertSucceeds(updateDoc(doc(db, 'items', itemId), { reportCount: 0 }));
});

test('items: 관리자도 Cloudinary 정리 백엔드를 우회해 직접 삭제할 수 없다', async () => {
  const itemId = await seedItem('alice');
  const db = adminUser().firestore();
  await assertFails(deleteDoc(doc(db, 'items', itemId)));
});

// ---------------------------------------------------------------------------
// savedSearches — 예전에는 글 등록 시 클라이언트가 전체를 훑어 매칭하느라
// 모든 로그인 사용자에게 읽기가 열려 있었다(= 남의 저장 키워드가 uid와 함께
// 노출). 매칭을 백엔드로 옮기면서 본인만 읽도록 잠갔다.
// ---------------------------------------------------------------------------

test('savedSearches: 본인 구독 목록은 읽고 쓸 수 있다', async () => {
  const db = hallymUser('alice').firestore();
  await assertSucceeds(
    setDoc(doc(db, 'savedSearches', 'alice'), { keywords: ['지갑'], categories: [] }),
  );
  await assertSucceeds(getDoc(doc(db, 'savedSearches', 'alice')));
});

test('savedSearches: 다른 사람의 저장 키워드는 읽을 수 없다', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'savedSearches', 'bob'), {
      keywords: ['지갑'],
      categories: [],
    });
  });
  const db = hallymUser('alice').firestore();
  await assertFails(getDoc(doc(db, 'savedSearches', 'bob')));
});

test('savedSearches: 전체 목록을 훑는 쿼리도 막힌다', async () => {
  const db = hallymUser('alice').firestore();
  await assertFails(getDocs(collection(db, 'savedSearches')));
});

test('savedSearches: 다른 사람의 구독 목록에 쓸 수 없다', async () => {
  const db = hallymUser('alice').firestore();
  await assertFails(
    setDoc(doc(db, 'savedSearches', 'bob'), { keywords: ['가짜'], categories: [] }),
  );
});

// ---------------------------------------------------------------------------
// withdrawnUsers — 탈퇴 후 재가입 제한 기록. 클라이언트가 쓸 수 있으면
// 스스로 제한을 지우고 재가입할 수 있으므로 읽기·쓰기 모두 막는다.
// ---------------------------------------------------------------------------

test('withdrawnUsers: 로그인 사용자도 읽거나 지울 수 없다', async () => {
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'withdrawnUsers', 'somehash'), {
      reregisterAllowedAt: new Date(),
    });
  });
  const db = hallymUser('alice').firestore();
  await assertFails(getDoc(doc(db, 'withdrawnUsers', 'somehash')));
  await assertFails(deleteDoc(doc(db, 'withdrawnUsers', 'somehash')));
});

test('withdrawnUsers: 관리자도 클라이언트에서는 손댈 수 없다(백엔드 전용)', async () => {
  const db = adminUser().firestore();
  await assertFails(
    setDoc(doc(db, 'withdrawnUsers', 'somehash'), { reregisterAllowedAt: new Date() }),
  );
});

test('pushDeliveries: 로그인 사용자도 서버의 중복 발송 예약을 읽거나 쓸 수 없다', async () => {
  const db = hallymUser('alice').firestore();
  await assertFails(setDoc(doc(db, 'pushDeliveries', 'fake'), { type: 'chat_message' }));
  await assertFails(getDoc(doc(db, 'pushDeliveries', 'fake')));
});

// ---------------------------------------------------------------------------
// notifications 종류 제한 — 예전에는 종류를 안 봐서 아무나 임의 사용자에게
// 가짜 '신고 검토 결과' 같은 알림을 만들 수 있었다.
// ---------------------------------------------------------------------------

test('notifications: 일반 사용자는 keyword_match 알림을 만들 수 없다(백엔드 전용)', async () => {
  const db = hallymUser('alice').firestore();
  await assertFails(
    addDoc(collection(db, 'notifications'), {
      recipientUid: 'bob',
      senderUid: 'alice',
      type: 'keyword_match',
      read: false,
    }),
  );
});

test('notifications: 일반 사용자는 가짜 신고 처리 알림을 만들 수 없다', async () => {
  const db = hallymUser('alice').firestore();
  for (const type of ['report_result', 'item_hidden', 'item_removed']) {
    await assertFails(
      addDoc(collection(db, 'notifications'), {
        recipientUid: 'bob',
        senderUid: 'alice',
        type,
        read: false,
      }),
    );
  }
});

test('notifications: 관리자는 신고 처리 결과 알림을 만들 수 있다', async () => {
  const db = adminUser().firestore();
  for (const type of ['report_result', 'item_hidden', 'item_removed']) {
    await assertSucceeds(
      addDoc(collection(db, 'notifications'), {
        recipientUid: 'bob',
        senderUid: 'admin',
        type,
        read: false,
      }),
    );
  }
});

// ---------------------------------------------------------------------------
// items.searchTokens — 서버 검색용 2-gram 배열.
// ---------------------------------------------------------------------------

test('items: searchTokens 배열을 담아 글을 등록할 수 있다', async () => {
  const db = hallymUser('alice').firestore();
  await assertSucceeds(
    addDoc(
      collection(db, 'items'),
      validItem('alice', { searchTokens: ['검은', '은색'] }),
    ),
  );
});

test('items: searchTokens가 배열이 아니면 거부된다', async () => {
  const db = hallymUser('alice').firestore();
  await assertFails(
    addDoc(collection(db, 'items'), validItem('alice', { searchTokens: '검은색' })),
  );
});

test('items: 수정할 때도 searchTokens 타입을 검증한다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('alice').firestore();
  await assertSucceeds(
    updateDoc(doc(db, 'items', itemId), { title: '새 제목', searchTokens: ['새제'] }),
  );
  await assertFails(
    updateDoc(doc(db, 'items', itemId), { title: '새 제목', searchTokens: 123 }),
  );
});

test('reports: 관리자는 신고 문서를 읽고 삭제할 수 있다', async () => {
  const itemId = await seedItem('alice');
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'reports', `${itemId}_bob`), {
      itemId,
      itemTitle: '검은색 백팩',
      authorUid: 'alice',
      reporterUid: 'bob',
      reason: '스팸/광고',
    });
  });
  const db = adminUser().firestore();
  await assertSucceeds(getDoc(doc(db, 'reports', `${itemId}_bob`)));
  await assertSucceeds(deleteDoc(doc(db, 'reports', `${itemId}_bob`)));
});

test('bugReports: 로그인 사용자는 본인 명의로 버그 신고를 생성할 수 있다', async () => {
  const db = hallymUser('alice').firestore();
  await assertSucceeds(
    addDoc(collection(db, 'bugReports'), {
      reporterUid: 'alice',
      reporterEmail: HALLYM_EMAIL('alice'),
      reporterNickname: '앨리스',
      content: '앱이 느려요',
      createdAt: serverTimestamp(),
    }),
  );
});

test('bugReports: 다른 사람 명의로 버그 신고를 생성할 수 없다', async () => {
  const db = hallymUser('alice').firestore();
  await assertFails(
    addDoc(collection(db, 'bugReports'), {
      reporterUid: 'bob',
      reporterEmail: HALLYM_EMAIL('alice'),
      reporterNickname: '앨리스',
      content: '위조',
      createdAt: serverTimestamp(),
    }),
  );
});

test('bugReports: 일반 사용자는 읽을 수 없고 관리자만 읽을 수 있다', async () => {
  let id;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const ref = await addDoc(collection(ctx.firestore(), 'bugReports'), {
      reporterUid: 'alice',
      content: '버그',
    });
    id = ref.id;
  });
  const user = hallymUser('alice').firestore();
  await assertFails(getDoc(doc(user, 'bugReports', id)));
  const admin = adminUser().firestore();
  await assertSucceeds(getDoc(doc(admin, 'bugReports', id)));
});

test('fcmTokens: 본인은 자기 토큰 문서를 읽고 쓸 수 있다', async () => {
  const db = hallymUser('alice').firestore();
  await assertSucceeds(
    setDoc(doc(db, 'fcmTokens', 'alice'), {
      tokens: ['token-a'],
      updatedAt: serverTimestamp(),
    }),
  );
  await assertSucceeds(getDoc(doc(db, 'fcmTokens', 'alice')));
});

test('fcmTokens: 갱신 시각이 없거나 클라이언트가 조작한 토큰 문서는 거부한다', async () => {
  const db = hallymUser('alice').firestore();
  await assertFails(
    setDoc(doc(db, 'fcmTokens', 'alice'), { tokens: ['token-a'] }),
  );
  await assertFails(
    setDoc(doc(db, 'fcmTokens', 'alice'), {
      tokens: ['token-a'],
      updatedAt: new Date(0),
    }),
  );
});

test('fcmTokens: 남의 토큰 문서는 읽거나 쓸 수 없다', async () => {
  const db = hallymUser('bob').firestore();
  await assertFails(
    setDoc(doc(db, 'fcmTokens', 'alice'), { tokens: ['token-x'] }),
  );
  await assertFails(getDoc(doc(db, 'fcmTokens', 'alice')));
});

test('userSettings: notifyChatMessage 등 알림 설정 키를 본인이 저장할 수 있다', async () => {
  const db = hallymUser('alice').firestore();
  await assertSucceeds(
    setDoc(doc(db, 'userSettings', 'alice'), {
      notifyChatMessage: false,
      notifyChatStarted: true,
    }),
  );
});

test('userSettings: 허용되지 않은 키는 저장할 수 없다', async () => {
  const db = hallymUser('alice').firestore();
  await assertFails(
    setDoc(doc(db, 'userSettings', 'alice'), { isAdmin: true }),
  );
});

/** 규칙을 우회해 items 문서를 심고 새 문서 id를 반환한다. */
async function seedItem(authorUid, overrides = {}) {
  let itemId;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    const ref = await addDoc(
      collection(ctx.firestore(), 'items'),
      validItem(authorUid, overrides),
    );
    itemId = ref.id;
  });
  return itemId;
}

/** 규칙을 우회해 두 참여자의 chats 문서를 심고 문서 id를 반환한다. */
async function seedChat(uidA, uidB, overrides = {}) {
  const chatId = `chat_${uidA}_${uidB}`;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'chats', chatId), {
      participants: [uidA, uidB],
      itemId: 'item1',
      itemAuthorUid: uidB,
      lastMessage: '',
      resolutionStatus: 'none',
      ...overrides,
    });
  });
  return chatId;
}
