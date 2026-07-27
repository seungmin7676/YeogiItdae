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
const { doc, getDoc, setDoc, updateDoc, deleteDoc, addDoc, collection, getDocs, query, where } = require('firebase/firestore');

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

/** 관리자 계정(firestore.rules의 isAdmin 이메일과 일치). uid는 무관하다. */
function adminUser() {
  return testEnv.authenticatedContext('admin', {
    email: '20225216@hallym.ac.kr',
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

test('items: 작성자 본인은 자유롭게 글을 수정할 수 있다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('alice').firestore();
  await assertSucceeds(updateDoc(doc(db, 'items', itemId), { title: '수정된 제목' }));
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

test('items: 작성자가 아닌 사용자는 reportCount를 정확히 +1만 할 수 있다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('bob').firestore();
  await assertSucceeds(updateDoc(doc(db, 'items', itemId), { reportCount: 1 }));
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

test('items: 작성자만 글을 삭제할 수 있다', async () => {
  const itemId = await seedItem('alice');
  const other = hallymUser('bob').firestore();
  await assertFails(deleteDoc(doc(other, 'items', itemId)));

  const owner = hallymUser('alice').firestore();
  await assertSucceeds(deleteDoc(doc(owner, 'items', itemId)));
});

test('items: 읽기는 로그인 없이도 가능하다', async () => {
  const itemId = await seedItem('alice');
  const db = testEnv.unauthenticatedContext().firestore();
  await assertSucceeds(getDoc(doc(db, 'items', itemId)));
});

test('reports: 본인 명의로만, 그리고 문서ID가 itemId_uid 형식이어야 신고할 수 있다', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('bob').firestore();
  await assertSucceeds(
    setDoc(doc(db, 'reports', `${itemId}_bob`), {
      itemId,
      reporterUid: 'bob',
      reason: '스팸/광고',
    }),
  );
});

test('reports: 문서ID가 본인 uid와 일치하지 않으면 신고할 수 없다(중복 신고 방지 우회 차단)', async () => {
  const itemId = await seedItem('alice');
  const db = hallymUser('bob').firestore();
  await assertFails(
    setDoc(doc(db, 'reports', `${itemId}_carol`), {
      itemId,
      reporterUid: 'bob',
      reason: '스팸/광고',
    }),
  );
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
  const db = hallymUser('alice').firestore();
  await assertSucceeds(
    setDoc(doc(db, 'userPrivate', 'alice'), {
      nickname: '테스트',
      realName: '홍길동',
      department: '컴퓨터공학과',
      studentId: '20240001',
      email: HALLYM_EMAIL('alice'),
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
      studentId: '20240001',
      email: HALLYM_EMAIL('alice'),
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
  const db = hallymUser('alice').firestore();
  await assertFails(
    setDoc(doc(db, 'chats', 'chat1'), {
      participants: ['alice'],
      itemId: 'item1',
      itemAuthorUid: 'bob',
      lastMessage: '',
    }),
  );
});

test('chats: 본인이 참여자에 포함되어야 채팅방을 만들 수 있다', async () => {
  const db = hallymUser('alice').firestore();
  await assertSucceeds(
    setDoc(doc(db, 'chats', 'chat1'), {
      participants: ['alice', 'bob'],
      itemId: 'item1',
      itemAuthorUid: 'bob',
      lastMessage: '',
    }),
  );
});

test('chats: 참여자는 lastMessage 같은 진행 필드를 수정할 수 있다', async () => {
  const chatId = await seedChat('alice', 'bob');
  const db = hallymUser('alice').firestore();
  await assertSucceeds(updateDoc(doc(db, 'chats', chatId), { lastMessage: '안녕하세요' }));
});

test('chats: 참여자라도 participants 같은 고정 필드는 수정할 수 없다', async () => {
  const chatId = await seedChat('alice', 'bob');
  const db = hallymUser('alice').firestore();
  await assertFails(
    updateDoc(doc(db, 'chats', chatId), { participants: ['alice', 'carol'] }),
  );
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

test('notifications: 발신자 본인 명의로만 알림을 생성할 수 있다', async () => {
  const db = hallymUser('alice').firestore();
  await assertSucceeds(
    addDoc(collection(db, 'notifications'), {
      recipientUid: 'bob',
      senderUid: 'alice',
      type: 'chat_started',
      read: false,
    }),
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

test('items: 관리자는 신고 반려로 reportCount를 0으로 초기화할 수 있다', async () => {
  const itemId = await seedItem('alice', { reportCount: 5 });
  const db = adminUser().firestore();
  await assertSucceeds(updateDoc(doc(db, 'items', itemId), { reportCount: 0 }));
});

test('items: 관리자는 신고 검토 결과로 남의 글도 삭제할 수 있다', async () => {
  const itemId = await seedItem('alice');
  const db = adminUser().firestore();
  await assertSucceeds(deleteDoc(doc(db, 'items', itemId)));
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
      content: '앱이 느려요',
    }),
  );
});

test('bugReports: 다른 사람 명의로 버그 신고를 생성할 수 없다', async () => {
  const db = hallymUser('alice').firestore();
  await assertFails(
    addDoc(collection(db, 'bugReports'), {
      reporterUid: 'bob',
      content: '위조',
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
    setDoc(doc(db, 'fcmTokens', 'alice'), { tokens: ['token-a'] }),
  );
  await assertSucceeds(getDoc(doc(db, 'fcmTokens', 'alice')));
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
async function seedChat(uidA, uidB) {
  const chatId = `chat_${uidA}_${uidB}`;
  await testEnv.withSecurityRulesDisabled(async (ctx) => {
    await setDoc(doc(ctx.firestore(), 'chats', chatId), {
      participants: [uidA, uidB],
      itemId: 'item1',
      itemAuthorUid: uidB,
      lastMessage: '',
    });
  });
  return chatId;
}
