// firebase-admin v14부터 루트 패키지는 모듈형 API만 내보낸다. 백엔드의
// 기존 호출부를 한 번에 안전하게 이관할 수 있도록, 모듈형 함수와 타입을
// 한곳에서 조합한 작은 호환 어댑터를 제공한다.
const { cert, getApps, initializeApp } = require('firebase-admin/app');
const { getAppCheck } = require('firebase-admin/app-check');
const { getAuth } = require('firebase-admin/auth');
const {
  FieldPath,
  FieldValue,
  Timestamp,
  getFirestore,
} = require('firebase-admin/firestore');
const { getMessaging } = require('firebase-admin/messaging');

function firestore() {
  return getFirestore();
}

firestore.FieldPath = FieldPath;
firestore.FieldValue = FieldValue;
firestore.Timestamp = Timestamp;

module.exports = {
  get apps() {
    return getApps();
  },
  initializeApp,
  credential: { cert },
  auth: getAuth,
  appCheck: getAppCheck,
  firestore,
  messaging: getMessaging,
};
