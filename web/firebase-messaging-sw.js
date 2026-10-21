// notificationclick을 Firebase 기본 핸들러보다 먼저 등록해 앱 안의 대상 화면을 연다.
self.addEventListener('notificationclick', (event) => {
  event.stopImmediatePropagation();
  event.notification.close();
  const data = event.notification.data?.FCM_MSG?.data || event.notification.data || {};
  const target = new URL('./', self.location.href);
  if (data.type) target.searchParams.set('pushType', data.type);
  if (data.chatId) target.searchParams.set('pushChatId', data.chatId);
  if (data.itemId) target.searchParams.set('pushItemId', data.itemId);
  event.waitUntil(self.clients.openWindow(target.href));
});

importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-app-compat.js');
importScripts('https://www.gstatic.com/firebasejs/12.18.0/firebase-messaging-compat.js');
firebase.initializeApp({
  apiKey: 'AIzaSyAYPGUm-L5zawGBBD2C_FkaTH0aQddr7SM',
  appId: '1:450095922894:web:1b35dae03733385471da9f',
  messagingSenderId: '450095922894',
  projectId: 'yeogi-itdae',
  authDomain: 'yeogi-itdae.firebaseapp.com',
  storageBucket: 'yeogi-itdae.firebasestorage.app',
});
firebase.messaging();
