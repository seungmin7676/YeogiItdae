const admin = require('firebase-admin');

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
    return await admin.auth().verifyIdToken(idToken);
  } catch (e) {
    res.status(401).json({ error: 'invalid-token' });
    return null;
  }
}

// 로그인 전(비밀번호 재설정 등)이라 requireUser로 발신자를 특정할 수 없는
// 엔드포인트에서, 최소한 "진짜 이 앱에서 온 요청인지"만이라도 확인하기
// 위한 App Check 검증. 학번 패턴을 순회하며 임의 주소로 메일을 대량
// 발송시키는 남용을 막는 게 목적이다.
//
// 클라이언트 배포·Firebase 콘솔에서의 App Check 활성화(Android는 Play
// Integrity API 활성화 및 SHA-256 지문 등록, iOS는 App Attest 사용 설정)가
// 아직 안 됐을 수 있으므로, 기본값은 실패해도 요청을 막지 않고 로그만
// 남긴다. 콘솔 설정과 클라이언트 배포를 확인한 뒤 APP_CHECK_ENFORCE=true
// 환경변수를 설정하면 실제로 차단한다.
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
  if (process.env.APP_CHECK_ENFORCE === 'true') {
    res.status(401).json({ error: 'app-check-failed' });
    return false;
  }
  return true;
}

module.exports = {
  initAdmin,
  setCors,
  requireUser,
  checkAppCheck,
  enforceAppCheckIfConfigured,
  ALLOWED_EMAIL_DOMAIN,
};
