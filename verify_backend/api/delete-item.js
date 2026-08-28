const {
  initAdmin,
  setCors,
  requireUser,
  enforceAppCheckIfConfigured,
  enforceRateLimit,
  isVerifiedHallymUser,
} = require('../_lib');
const { deleteCloudinaryUrls } = require('../_cloudinary');

const ADMIN_EMAIL = '20225216@hallym.ac.kr';
const BATCH_SIZE = 450;

async function deleteDocumentsInBatches(db, documents) {
  for (let i = 0; i < documents.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const document of documents.slice(i, i + BATCH_SIZE)) {
      batch.delete(document.ref);
    }
    await batch.commit();
  }
}

module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  if (!(await enforceAppCheckIfConfigured(req, res, 'delete-item'))) return;
  const decoded = await requireUser(req, res);
  if (!decoded) return;
  if (!isVerifiedHallymUser(decoded)) {
    return res.status(403).json({ error: 'verified-hallym-user-required' });
  }
  if (!(await enforceRateLimit(admin, req, res, {
    scope: 'delete-item-user',
    identifier: decoded.uid,
    max: 30,
    windowMs: 60 * 60 * 1000,
  }))) return;

  const itemId = typeof req.body?.itemId === 'string' ? req.body.itemId.trim() : '';
  if (!itemId || itemId.includes('/')) {
    return res.status(400).json({ error: 'invalid-item-id' });
  }
  const db = admin.firestore();
  const itemRef = db.collection('items').doc(itemId);
  const itemDoc = await itemRef.get();
  if (!itemDoc.exists) return res.status(404).json({ error: 'item-not-found' });
  const item = itemDoc.data() || {};
  const isAdmin = decoded.email === ADMIN_EMAIL && decoded.email_verified === true;
  if (item.authorUid !== decoded.uid && !isAdmin) {
    return res.status(403).json({ error: 'not-author' });
  }

  await deleteCloudinaryUrls(Array.isArray(item.imageUrls) ? item.imageUrls : []);

  const [chats, reports, notifications, appeal] = await Promise.all([
    db.collection('chats').where('itemId', '==', itemId).get(),
    db.collection('reports').where('itemId', '==', itemId).get(),
    db.collection('notifications').where('itemId', '==', itemId).get(),
    db.collection('reportAppeals').doc(itemId).get(),
  ]);
  for (let i = 0; i < chats.docs.length; i += BATCH_SIZE) {
    const batch = db.batch();
    for (const chat of chats.docs.slice(i, i + BATCH_SIZE)) {
      batch.set(chat.ref, { itemDeleted: true }, { merge: true });
    }
    await batch.commit();
  }

  // 게시글을 가리키는 운영 데이터도 함께 없애 참조가 끊긴 신고·알림·이의
  // 제기가 남지 않게 한다. 채팅방은 상대방의 대화 기록이므로 껍데기만 남기고
  // 위에서 삭제된 게시글임을 표시한다.
  await deleteDocumentsInBatches(db, reports.docs);
  await deleteDocumentsInBatches(db, notifications.docs);
  if (appeal.exists) await appeal.ref.delete();
  await itemRef.delete();
  return res.status(200).json({
    ok: true,
    chatsUpdated: chats.size,
    reportsDeleted: reports.size,
    notificationsDeleted: notifications.size,
    appealDeleted: appeal.exists,
  });
};
