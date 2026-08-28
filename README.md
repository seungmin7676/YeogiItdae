# 여기있대!

한림대학교 구성원을 위한 분실물 게시·검색·채팅·알림 앱입니다. Flutter 모바일
클라이언트, Firebase Authentication/Firestore/App Check/FCM, Cloudinary 이미지
저장소, Vercel Node 백엔드로 구성됩니다.

## 로컬 검증

```powershell
flutter pub get
flutter analyze
flutter test
flutter build apk --debug
flutter run -d emulator-5554
```

Firestore 규칙과 백엔드는 각각 Firebase Auth/Firestore 에뮬레이터에서 검증합니다.

```powershell
Set-Location firestore_tests
npm install
npm test

Set-Location ..\verify_backend
npm install
npm test
npm audit --omit=dev
```

Node.js 22 이상과 Flutter SDK가 필요합니다. 백엔드 테스트는 공유 에뮬레이터를
사용하므로 테스트 동시 실행 수를 변경하지 마세요.

## 릴리스 서명

Android 릴리스 빌드는 실제 업로드 키가 없으면 의도적으로 실패합니다.
`android/key.properties.example`을 `android/key.properties`로 복사하고 실제 키
정보를 넣으세요. `key.properties`와 `*.jks`는 Git에서 제외됩니다.

```powershell
flutter build appbundle --release
```

운영 배포 순서와 콘솔에서 확인해야 할 항목은
[DEPLOYMENT_CHECKLIST.md](DEPLOYMENT_CHECKLIST.md)를 따릅니다. Android 전시 빌드는
고유 식별자 `io.github.seungmin7676.yeogiitdae`와 별도 Firebase 앱을 사용합니다.
