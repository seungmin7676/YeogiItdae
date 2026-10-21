# 개발자 가이드

일반적인 앱 설치·사용 방법은 [README](../README.md)를 참고하세요.
이 문서는 소스 코드로 실행하거나 서버를 관리할 때 사용하는 안내입니다.

## 구성과 개발 환경

- Flutter 모바일·웹 클라이언트
- Firebase Authentication, Firestore, App Check, FCM, Crashlytics, Analytics
- Cloudinary 이미지 저장소
- Vercel Node.js 백엔드 (`verify_backend`)

v1.0.3 검증에 사용한 환경은 Flutter 3.44.4 / Dart 3.12.2입니다.
백엔드는 Node.js 22.x를 대상으로 합니다. Firebase 에뮬레이터 테스트에는 Java 21 이상이 필요합니다.

## 앱 실행과 테스트

저장소 루트에서 실행합니다.

```powershell
flutter pub get
flutter analyze lib test
flutter test
flutter devices
flutter run -d <기기-ID>
```

Firestore 규칙과 백엔드는 운영 데이터가 아닌 `demo-yeogi-itdae` 프로젝트의 에뮬레이터에서 검증합니다.

```powershell
Set-Location firestore_tests
npm install
npm test

Set-Location ../verify_backend
npm install
npm test
npm audit --omit=dev
```

각 테스트는 공유 에뮬레이터의 데이터를 초기화합니다. 두 테스트 묶음을 동시에 실행하거나
`--test-concurrency=1` 설정을 변경하지 마세요. Android Studio에 포함된 Java 21 이상을 사용한다면
해당 `jbr` 경로를 `JAVA_HOME`으로 설정할 수 있습니다.

## Android 전시용 빌드

Android application ID는 `io.github.seungmin7676.yeogiitdae`입니다.
릴리스 빌드에는 기존 서명 키와 로컬 `android/key.properties`가 필요합니다.
처음 설정하는 개발자는 `android/key.properties.example`을 참고하세요.
기존 앱을 업데이트하려면 같은 서명 키를 유지해야 합니다.

`key.properties`, `*.jks`, 서비스 계정과 서버 비밀키는 Git이나 릴리즈에 올리지 마세요.

```powershell
flutter build apk --release --dart-define=APP_CHECK_ENABLED=false
```

출력 파일은 `build/app/outputs/flutter-apk/app-release.apk`입니다.
GitHub 릴리즈에는 `YeogiItdae-v<버전>.apk`와 같이 버전을 붙여 첨부합니다.

이 명령은 Google Play가 아닌 교내 전시용입니다. Play Integrity 토큰을 요청하지 않으므로
운영 백엔드의 `APP_CHECK_ENFORCE=false` 설정과 짝을 맞춰야 합니다.
사용자 인증과 요청 횟수 제한은 유지됩니다. 스토어 배포 전에는 App Check 설정을 다시 점검하세요.

## 웹 빌드와 알림

```powershell
flutter build web --release --dart-define=APP_CHECK_ENABLED=false
```

웹 알림은 HTTPS 또는 localhost와 브라우저 알림 권한이 필요합니다.
필요하면 Firebase의 공개 VAPID 키를 `--dart-define=FCM_WEB_VAPID_KEY=<공개-키>`로 전달하세요.
`web/firebase-messaging-sw.js`도 웹 빌드와 함께 제공해야 합니다.
웹 빌드 성공은 실제 브라우저의 백그라운드 알림 수신을 검증한 것과 다릅니다.

## v1.0.3 서버 반영과 동작 특성

새 앱보다 `verify_backend`를 먼저 배포해야 합니다. 차단으로 인한 전송 거부 판별과
알림 재시도에는 이번 서버 코드가 필요합니다. Vercel 프로젝트의 Root Directory 설정에
맞는 경로에서 배포하고, 백엔드 주소가 바뀌면 `lib/services/backend_exception.dart`도 갱신하세요.

- 채팅은 최근 50건을 실시간으로 받고 이전 메시지는 문서 커서로 나눠 읽습니다.
- 일반 권한 오류를 전송 성공으로 표시하지 않습니다. 서버에서 차단을 확인한 경우에만
  텍스트·사진을 발신자 기기의 로컬 기록으로 남깁니다. 차단된 사진은 서버 채팅에 저장하지 않습니다.
- 실패한 알림 요청은 계정별로 보관하며 앱 실행·복귀 시 최대 24시간 동안 재시도합니다.
  성공한 기기별 전송 기록을 이용해 부분 실패 재시도의 중복을 줄입니다. 앱이 꺼진 동안의
  발송이나 OS에서 차단한 푸시 수신을 보장하는 서버 작업 큐는 아닙니다.
- 이미지 업로드는 응답 본문까지 포함해 45초 제한을 적용합니다.
- 검색은 기존 검색 토큰과 무관하게 제목·설명을 커서로 조회하고, 필요한 결과가 모이면 멈춥니다.
  데이터가 커지면 검색 범위에 따른 읽기 비용과 응답 시간을 다시 측정해야 합니다.
- 튜토리얼 확인 여부를 로컬에도 저장하고 원격 저장 실패가 앱 진입을 막지 않도록 했습니다.
- 소유자 확인과 사진 속 개인정보 보호는 안내로 보완합니다. 자동 소유권 판정·이미지 검열 기능은 아닙니다.

## 검증 기록과 남은 수동 확인

v1.0.3 코드 검증: Flutter 정적 분석, Flutter 테스트 138개, 백엔드 테스트 83개,
Android 릴리스 APK 및 웹 릴리스 빌드가 통과했습니다.

실제 Android 휴대폰에서 알림 권한 허용·거부, 포그라운드·백그라운드·종료 상태 푸시,
네트워크 단절·복구를 확인해야 합니다. iOS 배포 검증은 이 기록에 포함되지 않습니다.
운영 설정·서명·외부 서비스와 스토어 배포 준비 사항은 [배포 점검표](../DEPLOYMENT_CHECKLIST.md)를 따르세요.
