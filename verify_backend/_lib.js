const admin = require('firebase-admin');

const ALLOWED_EMAIL_DOMAIN = '@hallym.ac.kr';

function initAdmin() {
  if (admin.apps.length) return admin;
  const json = Buffer.from(process.env.FIREBASE_SERVICE_ACCOUNT_BASE64, 'base64').toString('utf8');
  const serviceAccount = JSON.parse(json);
  admin.initializeApp({ credential: admin.credential.cert(serviceAccount) });
  return admin;
}

function setCors(res) {
  res.setHeader('Access-Control-Allow-Origin', '*');
  res.setHeader('Access-Control-Allow-Methods', 'POST, OPTIONS');
  res.setHeader('Access-Control-Allow-Headers', 'Content-Type, Authorization');
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

module.exports = { initAdmin, setCors, requireUser, ALLOWED_EMAIL_DOMAIN };
