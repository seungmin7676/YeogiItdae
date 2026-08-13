/// 로그인 허용 이메일 도메인 (한림대학교 웹메일)
const String kAllowedEmailDomain = '@hallym.ac.kr';

/// 이메일 인증 코드 발송/검증을 담당하는 Vercel 백엔드 주소
const String kVerifyBackendUrl = 'https://verifybackend-eight.vercel.app';

class BackendException implements Exception {
  final String code;

  /// 오류 응답 본문 전체. 코드 외에 함께 내려오는 값(예: 재가입 제한의
  /// daysLeft)을 화면에서 쓰기 위해 그대로 들고 있는다.
  final Map<String, dynamic> data;

  BackendException(this.code, {this.data = const {}});

  /// 응답 본문의 정수 값을 꺼낸다(없으면 null).
  int? intValue(String key) => (data[key] as num?)?.toInt();
}
