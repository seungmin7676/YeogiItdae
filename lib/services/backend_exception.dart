/// 로그인 허용 이메일 도메인 (한림대학교 웹메일)
const String kAllowedEmailDomain = '@hallym.ac.kr';

/// 이메일 인증 코드 발송/검증을 담당하는 Vercel 백엔드 주소
const String kVerifyBackendUrl = 'https://verifybackend-eight.vercel.app';

class BackendException implements Exception {
  final String code;
  BackendException(this.code);
}
