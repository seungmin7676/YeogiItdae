const { initAdmin, setCors, requireUser } = require('../_lib');

module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  const decoded = await requireUser(req, res);
  if (!decoded) return;

  const inputCode = (req.body?.code ?? '').toString().trim();
  if (!inputCode) return res.status(400).json({ error: 'missing-code' });

  const db = admin.firestore();
  const docRef = db.collection('emailVerificationCodes').doc(decoded.uid);
  const snap = await docRef.get();
  if (!snap.exists) return res.status(404).json({ error: 'no-code' });

  const data = snap.data();
  if (Date.now() > data.expiresAt.toMillis()) {
    await docRef.delete();
    return res.status(410).json({ error: 'expired' });
  }

  if ((data.attempts ?? 0) >= 5) {
    await docRef.delete();
    return res.status(429).json({ error: 'too-many-attempts' });
  }

  if (data.code !== inputCode) {
    await docRef.update({ attempts: admin.firestore.FieldValue.increment(1) });
    return res.status(400).json({ error: 'wrong-code' });
  }

  await admin.auth().updateUser(decoded.uid, { emailVerified: true });
  await docRef.delete();

  return res.status(200).json({ ok: true });
};
