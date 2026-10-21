const { test } = require('node:test');
const assert = require('node:assert/strict');
const { sendPushToUser } = require('../_push');

function fixture(responses) {
  const documents = new Map([['fcmTokens/bob', { tokens: ['phone', 'tablet'] }]]);
  const calls = [];
  const firestore = () => ({ collection: (collection) => ({ doc: (id) => ({
    get: async () => ({ exists: documents.has(`${collection}/${id}`), data: () => documents.get(`${collection}/${id}`) }),
    set: async (patch) => {
      const data = documents.get(`${collection}/${id}`) || {};
      for (const [key, value] of Object.entries(patch)) {
        if (value?.operation === 'union') data[key] = [...new Set([...(data[key] || []), ...value.values])];
        else if (value?.operation === 'remove') data[key] = (data[key] || []).filter((entry) => !value.values.includes(entry));
        else data[key] = value;
      }
      documents.set(`${collection}/${id}`, data);
    },
  }) }) });
  firestore.FieldValue = {
    arrayUnion: (...values) => ({ operation: 'union', values }),
    arrayRemove: (...values) => ({ operation: 'remove', values }),
  };
  firestore.Timestamp = { fromMillis: (value) => value };
  const admin = { firestore, messaging: () => ({ sendEachForMulticast: async (message) => {
    calls.push(message.tokens);
    const result = responses.shift();
    return { responses: result, successCount: result.filter((entry) => entry.success).length,
      failureCount: result.filter((entry) => !entry.success).length };
  } }) };
  return { admin, calls, documents };
}

const payload = { recipientUid: 'bob', senderUid: 'alice', type: 'chat_message',
  title: '앨리스', body: '메시지', data: { chatId: 'chat' }, deliveryKey: 'event-1' };

test('부분 실패를 재시도할 때 성공한 기기에는 중복 발송하지 않는다', async () => {
  const state = fixture([
    [{ success: true }, { success: false, error: { code: 'messaging/server-unavailable' } }],
    [{ success: true }],
  ]);
  assert.equal((await sendPushToUser(state.admin, payload)).retryable, true);
  assert.equal((await sendPushToUser(state.admin, payload)).failed, 0);
  assert.deepEqual(state.calls, [['phone', 'tablet'], ['tablet']]);
  await sendPushToUser(state.admin, payload);
  assert.equal(state.calls.length, 2);
});

test('만료된 기기 토큰은 제거하고 영구 오류를 무한 재시도하지 않는다', async () => {
  const state = fixture([[{ success: true }, {
    success: false, error: { code: 'messaging/registration-token-not-registered' },
  }]]);
  const result = await sendPushToUser(state.admin, payload);
  assert.equal(result.failed, 0);
  assert.equal(result.retryable, false);
  assert.deepEqual(state.documents.get('fcmTokens/bob').tokens, ['phone']);
});
