const { initAdmin, setCors, ALLOWED_EMAIL_DOMAIN } = require('../_lib');

module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  const email = (req.body?.email ?? '').toString().trim().toLowerCase();
  const resetToken = (req.body?.resetToken ?? '').toString().trim();
  const newPassword = (req.body?.newPassword ?? '').toString();

  if (!email || !email.endsWith(ALLOWED_EMAIL_DOMAIN)) {
    return res.status(403).json({ error: 'domain-not-allowed' });
  }
  if (!resetToken) return res.status(400).json({ error: 'missing-token' });
  if (newPassword.length < 8) return res.status(400).json({ error: 'weak-password' });

  let userRecord;
  try {
    userRecord = await admin.auth().getUserByEmail(email);
  } catch (e) {
    return res.status(404).json({ error: 'user-not-found' });
  }

  const db = admin.firestore();
  const docRef = db.collection('passwordResetCodes').doc(userRecord.uid);
  const snap = await docRef.get();
  if (!snap.exists) return res.status(404).json({ error: 'no-token' });

  const data = snap.data();
  if (!data.resetTokenExpiresAt || Date.now() > data.resetTokenExpiresAt.toMillis()) {
    await docRef.delete();
    return res.status(410).json({ error: 'expired' });
  }

  if (data.resetToken !== resetToken) {
    return res.status(400).json({ error: 'invalid-token' });
  }

  await admin.auth().updateUser(userRecord.uid, { password: newPassword });
  await docRef.delete();

  return res.status(200).json({ ok: true });
};
