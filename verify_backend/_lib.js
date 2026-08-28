const admin = require('./_admin');
const crypto = require('crypto');

const ALLOWED_EMAIL_DOMAIN = '@hallym.ac.kr';

function initAdmin() {
  if (admin.apps.length) return admin;
  // 에뮬레이터 대상 테스트에서는 실제 서비스 계정 자격증명이 없어도 되고,
  // 있어서도 안 된다(에뮬레이터 트래픽인데 진짜 프로젝트로 나가면 안 되므로).
  if (process.env.FIRESTORE_EMULATOR_HOST) {
    admin.initializeApp({ projectId: process.env.GCLOUD_PROJECT || 'demo-yeogi-itdae' });
    return admin;
  }
  const json = Buffer.from(process.env.FIREBASE_SERVICE_ACCOUNT_BASE64, 'base64').toString('utf8');
  const serviceAccount = JSON.parse(json);
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  return admin;
}

function setCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader(
    'Access-Control-Allow-Headers',
    'Content-Type, Authorization, X-Firebase-AppCheck',
  );
}

async function requireUser(req, res) {
  const authHeader = req.headers.authorization || '';
  const idToken = authHeader.startsWith('Bearer ') ? authHeader.slice(7) : null;
  if (!idToken) {
    res.status(401).json({ error: 'unauthenticated' });
    return null;
  }
  try {
    // 운영에서는 탈취된 토큰이 사용자가 로그아웃·탈퇴한 뒤에도 살아남지 않게
    // revoked 여부까지 확인한다. Auth 에뮬레이터는 이 원격 확인을 흉내내지
    // 못하므로 로컬 테스트에서만 생략한다.
    return await admin
      .auth()
      .verifyIdToken(idToken, !process.env.FIREBASE_AUTH_EMULATOR_HOST);
  } catch (e) {
    // 사유는 서버 로그에만 남기고, 클라이언트엔 일반화된 코드만 내려준다.
    console.error('[requireUser] verifyIdToken failed:', e.code, e.message);
    res.status(401).json({ error: 'invalid-token' });
    return null;
  }
}

// 로그인 전(비밀번호 재설정 등)이라 requireUser로 발신자를 특정할 수 없는
// 엔드포인트에서, 최소한 "진짜 이 앱에서 온 요청인지"만이라도 확인하기
// 위한 App Check 검증. 학번 패턴을 순회하며 임의 주소로 메일을 대량
// 발송시키는 남용을 막는 게 목적이다.
//
// 운영 기본값은 fail-closed다. 명시적으로 APP_CHECK_ENFORCE=false를 준
// 긴급 롤백과 Firebase 에뮬레이터 테스트에서만 검증 실패를 통과시킨다.
async function checkAppCheck(req) {
  const token = req.headers['x-firebase-appcheck'];
  if (!token) return { valid: false, reason: 'missing' };
  try {
    await admin.appCheck().verifyToken(token);
    return { valid: true };
  } catch (e) {
    return { valid: false, reason: 'invalid' };
  }
}

async function enforceAppCheckIfConfigured(req, res, label) {
  const result = await checkAppCheck(req);
  if (result.valid) return true;

  console.warn(`[app-check] ${label} 요청에 유효한 App Check 토큰이 없습니다: ${result.reason}`);
  const shouldEnforce =
    process.env.APP_CHECK_ENFORCE === 'true' ||
    (process.env.APP_CHECK_ENFORCE !== 'false' && !process.env.FIRESTORE_EMULATOR_HOST);
  if (shouldEnforce) {
    res.status(401).json({ error: 'app-check-failed' });
    return false;
  }
  return true;
}

function requestIp(req) {
  const forwarded = req.headers['x-forwarded-for'];
  if (typeof forwarded === 'string' && forwarded.trim()) {
    return forwarded.split(',')[0].trim();
  }
  return req.socket?.remoteAddress || req.connection?.remoteAddress || 'unknown';
}

/**
 * 서버리스 인스턴스가 여러 개 떠도 공유되는 Firestore 기반 고정 윈도 rate limit.
 * 문서 ID에는 IP·이메일·uid 원문을 남기지 않고 SHA-256만 저장한다.
 */
async function enforceRateLimit(
  adminInstance,
  req,
  res,
  { scope, identifier = '', max, windowMs },
) {
  const now = Date.now();
  const windowStartMs = Math.floor(now / windowMs) * windowMs;
  const rawKey = `${scope}|${requestIp(req)}|${String(identifier).toLowerCase()}|${windowStartMs}`;
  const key = crypto.createHash('sha256').update(rawKey).digest('hex');
  const ref = adminInstance.firestore().collection('rateLimits').doc(key);

  const allowed = await adminInstance.firestore().runTransaction(async (tx) => {
    const doc = await tx.get(ref);
    const count = doc.exists ? Number(doc.data().count || 0) : 0;
    if (count >= max) return false;
    tx.set(
      ref,
      {
        scope,
        count: count + 1,
        windowStartMs,
        expiresAt: adminInstance.firestore.Timestamp.fromMillis(
          windowStartMs + windowMs * 2,
        ),
      },
      { merge: true },
    );
    return true;
  });

  if (!allowed) {
    res.status(429).json({ error: 'rate-limit' });
    return false;
  }
  return true;
}

function isVerifiedHallymUser(decoded) {
  return (
    decoded &&
    decoded.email_verified === true &&
    typeof decoded.email === 'string' &&
    decoded.email.toLowerCase().endsWith(ALLOWED_EMAIL_DOMAIN)
  );
}

module.exports = {
  initAdmin,
  setCors,
  requireUser,
  checkAppCheck,
  enforceAppCheckIfConfigured,
  enforceRateLimit,
  isVerifiedHallymUser,
  ALLOWED_EMAIL_DOMAIN,
};
