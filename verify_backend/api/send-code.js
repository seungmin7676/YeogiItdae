const nodemailer = require('nodemailer');
const { initAdmin, setCors, requireUser, ALLOWED_EMAIL_DOMAIN } = require('../_lib');
const { checkWithdrawalCooldown } = require('../_withdrawal');

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

  // 탈퇴 후 재가입 제한. 여기가 실제 관문이다 — 가입 화면의 사전 확인
  // (signup-eligibility)을 건너뛰고 Auth 계정을 만들어도, 인증 코드를 못 받으면
  // 규칙상(isVerifiedHallymUser) 아무것도 할 수 없다.
  //
  // 이미 인증을 마친 계정은 검사하지 않는다. 제한은 "탈퇴한 명의로 새로 만든
  // 계정"에만 걸려야 하고, 인증까지 끝난 계정이 그 상태가 될 일은 없다.
  if (decoded.email_verified !== true) {
    const { blocked, daysLeft } = await checkWithdrawalCooldown(admin, email);
    if (blocked) {
      // 막을 거면 방금 만들어진 계정도 되돌린다. 그대로 두면 그 이메일이
      // 인증도 못 하고 재가입도 못 하는 껍데기 계정에 묶여버린다.
      // 가입 과정에서 먼저 쓰인 프로필 문서도 함께 정리한다.
      await Promise.all([
        admin.firestore().collection('userPublicProfiles').doc(decoded.uid).delete(),
        admin.firestore().collection('userPrivate').doc(decoded.uid).delete(),
      ]).catch((e) => console.error('[send-code] 롤백 정리 실패:', e.message));
      await admin
        .auth()
        .deleteUser(decoded.uid)
        .catch((e) => console.error('[send-code] 롤백 계정 삭제 실패:', e.message));
      return res.status(403).json({ error: 'withdrawn-cooldown', daysLeft });
    }
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
