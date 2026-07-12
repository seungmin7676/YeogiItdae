const crypto = require('crypto');
const { initAdmin, setCors, ALLOWED_EMAIL_DOMAIN } = require('../_lib');

const RESET_TOKEN_TTL_MS = 10 * 60 * 1000;

module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  const email = (req.body?.email ?? '').toString().trim().toLowerCase();
  const inputCode = (req.body?.code ?? '').toString().trim();

  if (!email || !email.endsWith(ALLOWED_EMAIL_DOMAIN)) {
    return res.status(403).json({ error: 'domain-not-allowed' });
  }
  if (!inputCode) return res.status(400).json({ error: 'missing-code' });

  let userRecord;
  try {
    userRecord = await admin.auth().getUserByEmail(email);
  } catch (e) {
    return res.status(404).json({ error: 'user-not-found' });
  }

  const db = admin.firestore();
  const docRef = db.collection('passwordResetCodes').doc(userRecord.uid);
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

  // 코드 확인이 끝나면 코드 자체는 더 이상 재사용할 수 없게 하고,
  // 다음 단계(새 비밀번호 설정)에서만 쓸 수 있는 일회용 토큰을 발급한다.
  const resetToken = crypto.randomBytes(24).toString('hex');
  await docRef.set({
    resetToken,
    email,
    resetTokenExpiresAt: admin.firestore.Timestamp.fromMillis(
      Date.now() + RESET_TOKEN_TTL_MS,
    ),
  });

  return res.status(200).json({ ok: true, resetToken });
};
