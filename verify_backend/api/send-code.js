const nodemailer = require('nodemailer');
const { initAdmin, setCors, requireUser, ALLOWED_EMAIL_DOMAIN } = require('../_lib');

const RESEND_COOLDOWN_MS = 60 * 1000;
const CODE_TTL_MS = 10 * 60 * 1000;

function generateCode() {
  return Math.floor(100000 + Math.random() * 900000).toString();
}

module.exports = async (req, res) => {
  setCors(res);
  if (req.method === 'OPTIONS') return res.status(204).end();
  if (req.method !== 'POST') return res.status(405).json({ error: 'method-not-allowed' });

  const admin = initAdmin();
  const decoded = await requireUser(req, res);
  if (!decoded) return;

  const email = decoded.email;
  if (!email || !email.toLowerCase().endsWith(ALLOWED_EMAIL_DOMAIN)) {
    return res.status(403).json({ error: 'domain-not-allowed' });
  }

  const db = admin.firestore();
  const docRef = db.collection('emailVerificationCodes').doc(decoded.uid);
  const existing = await docRef.get();
  if (existing.exists) {
    const data = existing.data();
    const lastSentAt = data.lastSentAt?.toMillis?.() ?? 0;
    if (Date.now() - lastSentAt < RESEND_COOLDOWN_MS) {
      return res.status(429).json({ error: 'cooldown' });
    }
  }

  const code = generateCode();
  await docRef.set({
    code,
    email,
    attempts: 0,
    expiresAt: admin.firestore.Timestamp.fromMillis(Date.now() + CODE_TTL_MS),
    lastSentAt: admin.firestore.FieldValue.serverTimestamp(),
  });

  const transporter = nodemailer.createTransport({
    service: 'gmail',
    auth: {
      user: process.env.SMTP_USER,
      pass: process.env.SMTP_PASS,
    },
  });

  await transporter.sendMail({
    from: `"여기있대!" <${process.env.SMTP_USER}>`,
    to: email,
    subject: '[여기있대!] 이메일 인증 코드',
    text: `여기있대! 인증 코드는 ${code} 입니다. 10분 이내에 입력해주세요.`,
    html: `
      <div style="font-family:sans-serif;padding:24px;color:#111;">
        <h2 style="color:#3F51B5;margin-bottom:8px;">여기있대! 이메일 인증</h2>
        <p>아래 인증 코드를 앱에 입력해주세요.</p>
        <p style="font-size:32px;font-weight:bold;letter-spacing:6px;margin:24px 0;">${code}</p>
        <p style="color:#888;font-size:12px;">코드는 10분간 유효합니다. 본인이 요청하지 않았다면 이 메일을 무시해주세요.</p>
      </div>
    `,
  });

  return res.status(200).json({ ok: true });
};
