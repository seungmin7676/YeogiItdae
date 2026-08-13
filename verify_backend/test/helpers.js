// Vercel 서버리스 핸들러는 (req, res) => {...} 형태로 res.status().json()을
// 쓰는데, 실제 HTTP 서버 없이 함수만 직접 호출해 테스트하기 위한 최소한의
// req/res 더미와, Auth 에뮬레이터에서 진짜 ID 토큰을 발급받는 헬퍼.
function mockReq({ method = 'POST', body = {}, headers = {} } = {}) {
  return { method, body, headers };
}

function mockRes() {
  return {
    statusCode: 200,
    _json: undefined,
    _ended: false,
    status(code) {
      this.statusCode = code;
      return this;
    },
    json(payload) {
      this._json = payload;
      return this;
    },
    end() {
      this._ended = true;
      return this;
    },
    setHeader() {},
  };
}

/** Auth 에뮬레이터에 테스트 계정을 만들고 ID 토큰을 발급받는다. */
async function signUpTestUser(email, password) {
  const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const response = await fetch(
    `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signUp?key=test-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const data = await response.json();
  if (!response.ok) {
    throw new Error(`signUp failed: ${JSON.stringify(data)}`);
  }
  return data; // { idToken, localId, ... }
}

/** Auth 에뮬레이터에서 기존 계정으로 로그인해 새 ID 토큰을 받는다. */
async function signInTestUser(email, password) {
  const authHost = process.env.FIREBASE_AUTH_EMULATOR_HOST;
  const response = await fetch(
    `http://${authHost}/identitytoolkit.googleapis.com/v1/accounts:signInWithPassword?key=test-key`,
    {
      method: 'POST',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify({ email, password, returnSecureToken: true }),
    },
  );
  const data = await response.json();
  if (!response.ok) {
    throw new Error(`signIn failed: ${JSON.stringify(data)}`);
  }
  return data; // { idToken, localId, ... }
}

/**
 * 이메일 인증까지 끝난 계정을 만들고 ID 토큰을 받는다.
 * 가입 직후 발급된 토큰에는 email_verified가 false로 박혀 있으므로,
 * 인증 상태로 바꾼 뒤 **다시 로그인해** 새 토큰을 받아야 한다.
 */
async function signUpVerifiedTestUser(admin, email, password) {
  const { localId } = await signUpTestUser(email, password);
  await admin.auth().updateUser(localId, { emailVerified: true });
  const { idToken } = await signInTestUser(email, password);
  return { idToken, localId };
}

module.exports = {
  mockReq,
  mockRes,
  signUpTestUser,
  signInTestUser,
  signUpVerifiedTestUser,
};
