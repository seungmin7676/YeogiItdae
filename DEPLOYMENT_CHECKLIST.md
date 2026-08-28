# 여기있대! 배포 체크리스트

이 문서는 코드만으로 확정하거나 실행할 수 없는 운영 콘솔 작업까지 포함합니다.
아래의 **필수** 항목이 하나라도 남아 있으면 스토어에 제출하지 마세요.

## 1. 앱 신원과 서명 — 필수

- [x] Android 전시용 application ID를
  `io.github.seungmin7676.yeogiitdae`로 확정하고 Firebase Android 앱,
  `google-services.json`, `lib/firebase_options.dart`, namespace/applicationId를
  같은 값으로 갱신했다.
- [ ] iOS를 실제 배포할 때 bundle ID를 확정하고 Firebase iOS 앱,
  `GoogleService-Info.plist`, `lib/firebase_options.dart`, Xcode 프로젝트 식별자를
  함께 갱신한다.
- [x] Android upload keystore를 생성하고 로컬 `android/key.properties`에 연결했다.
  키와 비밀번호는 저장소에서 제외되어 있다. 다른 안전한 장소에 두 파일을 함께
  백업하는 작업은 사용자가 수행한다.
- [ ] Apple Developer Team, 배포 인증서, App Store provisioning profile을 설정하고
  APNs 인증 키를 Firebase Cloud Messaging에 등록한다.
- [x] 첫 전시 프리릴리스 버전을 `1.0.0+1`로 확정했다.

## 2. Firebase 보안과 데이터 — 필수

- [x] Firebase App Check API를 활성화했다.
- [x] Android Play Integrity 제공자와 release 인증서 SHA-256을 등록했다. 현재
  Play Console 없이 진행하는 제한된 교내 전시에서는 사용하지 않고, 이후 스토어
  배포 때 Cloud project 연결까지 마친 뒤 활성화한다. iOS를 배포할 때는
  App Attest/DeviceCheck를 별도로 등록한다.
- [x] 현재 교내 전시용 GitHub APK는 Play Console 가입 없이
  `APP_CHECK_ENABLED=false`로 빌드하고 Vercel의 `APP_CHECK_ENFORCE=false`와
  짝을 맞춘다. Play Integrity는 사용하지 않지만 사용자 인증과 서버 rate limit은
  유지한다.
- [ ] Play Store 또는 불특정 다수 대상 배포 전에는 Google Play Console에
  Android 앱을 추가하고 Play Integrity API의 **Link Cloud project**에서
  `yeogi-itdae`를 연결한 뒤 App Check 클라이언트·서버 강제를 모두 다시 켠다.
- [x] `firestore.indexes.json`을 배포하고 Firebase에서 모든 인덱스가
  **Enabled** 상태가 될 때까지 기다린다. 배포 전 실제 피드 조회는 필요한 인덱스가
  없어 `FAILED_PRECONDITION`으로 실패한다.
- [x] 강화된 규칙을 배포하기 전에 운영 데이터에
  `hidden`, 검색 토큰, 저장 검색 토큰 백필을 완료하고 재검사에서 대상 0건을
  확인했다.
- [ ] 백필을 확인한 뒤 `firestore.rules`를 배포한다.
- [ ] Blaze 요금제를 사용할 때 Firestore TTL을 별도로 활성화한다: 인증/재설정
  코드, rate limit, 알림 전달 멱등 키, 탈퇴 제한 기록. 현재 전시용 Spark
  프로젝트는 TTL API가 결제를 요구하므로 기본 인덱스 배포에서 제외한다.
- [ ] 관리자 이메일 `20225216@hallym.ac.kr`이 실제 운영 관리자 계정인지 확인한다.
  변경한다면 규칙·백엔드·클라이언트의 관리자 상수를 함께 변경한다.

권장 순서:

1. App Check 제공자 설정
2. 백엔드 배포
3. Firestore 인덱스 배포 및 Enabled 확인
4. 두 백필 완료
5. Firestore 규칙 배포
6. 최종 앱 배포

## 3. 백엔드와 외부 서비스 — 필수

- [ ] Vercel 프로젝트의 Node 런타임을 22 이상으로 설정한다.
- [ ] `FIREBASE_SERVICE_ACCOUNT_BASE64`, `SMTP_USER`, `SMTP_PASS`,
  `CLOUDINARY_CLOUD_NAME`, `CLOUDINARY_API_KEY`, `CLOUDINARY_API_SECRET`,
  `CLOUDINARY_UPLOAD_PRESET`을 production 환경 변수로 설정한다.
- [ ] Cloudinary upload preset이 signed이고, 업로드가 `latte/<uid>` 폴더로만
  생성되는지 확인한다. API secret은 앱에 넣지 않는다.
- [ ] 백엔드 배포 주소가 바뀌면 `lib/services/backend_exception.dart`의
  `kVerifyBackendUrl`을 바꾸고 모든 API를 다시 테스트한다.
- [ ] Gmail SMTP 계정의 앱 비밀번호/발송 한도와 운영 장애 알림을 설정한다.
- [ ] Vercel 로그에 서비스 계정 JSON, ID token, App Check token, 인증 코드가
  기록되지 않는지 확인한다.

## 4. 개인정보와 스토어 정보 — 필수

- [ ] `web/privacy.html`과 `web/delete-account.html`을 로그인 없이 접근 가능한
  HTTPS 주소에 배포하고 Play Console 및 App Store Connect에 등록한다.
- [ ] 실제 Firebase·Cloudinary·Vercel·메일 처리 리전과 국외 이전 국가, 시점·방법,
  보유 기간을 운영 계약/콘솔에서 확인해 개인정보 처리방침에 구체적으로 반영한다.
  현재 문구는 해외 리전 가능성만 설명하므로 법률 검토 전 최종본이 아니다.
- [ ] Google Play Data safety 양식에 Firebase/Cloudinary 등 제3자 SDK가 수집하는
  데이터까지 포함해 사실대로 신고한다.
- [ ] App Store Connect의 App Privacy 응답을 `ios/Runner/PrivacyInfo.xcprivacy`와
  실제 수집 동작에 맞춘다. Analytics/Crashlytics 및 종속 SDK의 생성된 privacy
  report도 Xcode Organizer에서 확인한다.
- [ ] 개인정보 처리방침과 계정 삭제 요청 페이지의 운영 이메일로 실제 수신·회신
  테스트를 한다.

## 5. 최종 기기 검증 — 필수

- [ ] 아래 자동 검증을 모두 통과한다.
  - `flutter analyze`
  - `flutter test`
  - `flutter build appbundle --release`
  - `flutter build web --release`
  - `npm test` (`firestore_tests`, `verify_backend` 각각)
  - `npm audit --omit=dev` (`verify_backend`)
- [ ] 실제 Android 기기에서 Play 내부 테스트 트랙 빌드로 가입·메일 인증·로그인,
  글 작성/검색/수정/삭제, 카메라·갤러리, 찜·알림, 채팅·사진·차단·신고,
  백그라운드/종료 상태 푸시, 비밀번호 재설정, 회원 탈퇴를 확인한다.
- [ ] 실제 iPhone에서 TestFlight 빌드로 같은 흐름, 사진 권한, APNs 푸시,
  App Attest fallback을 확인한다. Windows 환경에서는 iOS archive를 검증할 수 없다.
- [ ] 큰 글자, 화면 회전, 네트워크 단절/복구, 중복 탭, 서버 오류, 빈 목록과 긴
  문자열을 확인한다.
- [ ] Crashlytics 테스트 오류가 수집되고 실제 사용자 개인정보가 로그에 남지 않는지
  확인한다.

## 6. 출시 직전 산출물

- [ ] AAB/IPA의 앱 이름, 아이콘, 버전, 패키지 ID와 서명이 최종 값인지 확인한다.
- [ ] 스토어 설명, 스크린샷, 지원 이메일, 개인정보 URL, 계정 삭제 URL을 등록한다.
- [ ] Firebase·Vercel·Cloudinary 예산 알림과 장애 모니터링을 설정한다.
- [ ] 규칙·인덱스·백엔드의 현재 운영 버전을 태그하고 롤백 방법을 기록한다.
