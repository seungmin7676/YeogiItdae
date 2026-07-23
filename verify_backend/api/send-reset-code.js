const nodemailer = require('nodemailer');
const { initAdmin, setCors, ALLOWED_EMAIL_DOMAIN, enforceAppCheckIfConfigured } = require('../_lib');

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

  // 로그인 전 화면이라 요청자를 특정할 수 없으니, 학번 패턴을 순회하며
  // 임의 주소로 메일을 대량 발송시키는 남용을 막기 위해 최소한 "진짜 앱에서
  // 온 요청인지"는 확인한다.
  if (!(await enforceAppCheckIfConfigured(req, res, 'send-reset-code'))) return;

  const email = (req.body?.email ?? '').toString().trim().toLowerCase();
  if (!email || !email.endsWith(ALLOWED_EMAIL_DOMAIN)) {
    return res.status(403).json({ error: 'domain-not-allowed' });
  }

  let userRecord;
  try {
    userRecord = await admin.auth().getUserByEmail(email);
  } catch (e) {
    return res.status(404).json({ error: 'user-not-found' });
  }

  const db = admin.firestore();
  const docRef = db.collection('passwordResetCodes').doc(userRecord.uid);
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
    subject: '[여기있대!] 비밀번호 재설정 코드',
    text: `비밀번호 재설정 코드는 ${code} 입니다. 10분 이내에 입력해주세요.`,
    html: `
      <div style="font-family:sans-serif;padding:24px;color:#111;">
        <h2 style="color:#3F51B5;margin-bottom:8px;">여기있대! 비밀번호 재설정</h2>
        <p>아래 인증 코드를 앱에 입력해주세요.</p>
        <p style="font-size:32px;font-weight:bold;letter-spacing:6px;margin:24px 0;">${code}</p>
        <p style="color:#888;font-size:12px;">코드는 10분간 유효합니다. 본인이 요청하지 않았다면 이 메일을 무시해주세요.</p>
      </div>
    `,
  });

  return res.status(200).json({ ok: true });
};
