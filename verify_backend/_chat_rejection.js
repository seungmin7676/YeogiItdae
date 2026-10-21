// 권한 오류를 차단으로 오인하지 않도록 인증된 실제 대화 관계만 검사한다.
// 상대방 차단 목록 자체는 클라이언트에 반환하지 않는다.
async function classifyChatRejection(db, uid, body) {
  const { chatId, recipientUid, itemId } = body;
  if (typeof chatId !== 'string' || !chatId || chatId.length > 1500 || chatId.includes('/') ||
      typeof recipientUid !== 'string' || recipientUid.includes('/') ||
      !recipientUid || recipientUid === uid) return false;
  const chat = await db.collection('chats').doc(chatId).get();
  if (chat.exists) {
    const participants = chat.data().participants;
    if (!Array.isArray(participants) || participants.length !== 2 ||
        !participants.includes(uid) || !participants.includes(recipientUid)) return false;
  } else {
    if (typeof itemId !== 'string' || !itemId || itemId.includes('/')) return false;
    const item = await db.collection('items').doc(itemId).get();
    if (!item.exists || item.data().authorUid !== recipientUid || item.data().hidden === true) return false;
    const expected = `${itemId}_${[uid, recipientUid].sort().join('_')}`;
    if (chatId !== expected) return false;
  }
  const [mine, peer] = await Promise.all([
    db.collection('blocks').doc(uid).get(),
    db.collection('blocks').doc(recipientUid).get(),
  ]);
  const contains = (snapshot, other) => {
    const blocked = snapshot.data()?.blockedUsers;
    return blocked && Object.prototype.hasOwnProperty.call(blocked, other);
  };
  return Boolean(contains(mine, recipientUid) || contains(peer, uid));
}

module.exports = { classifyChatRejection };
