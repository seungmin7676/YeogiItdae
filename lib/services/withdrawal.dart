import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'backend_exception.dart';
import 'backend_http.dart';

/// 탈퇴 후 재가입이 제한되는 기간(일).
///
/// **실제 판정은 서버가 한다** — verify_backend/_withdrawal.js의
/// WITHDRAWAL_COOLDOWN_DAYS와 반드시 같은 값으로 유지해야 한다. 여기 값은
/// 탈퇴 전에 "며칠 동안 못 돌아온다"고 미리 안내하는 용도로만 쓴다.
const int kWithdrawalCooldownDays = 30;

/// 탈퇴 후 재가입 제한에 걸렸을 때 던지는 예외. 남은 일수를 함께 전달한다.
class WithdrawnCooldownException implements Exception {
  final int daysLeft;

  const WithdrawnCooldownException(this.daysLeft);

  /// 가입 화면·인증 화면에서 그대로 보여줄 안내 문구.
  String get message =>
      '탈퇴한 계정과 같은 학번으로는 바로 다시 가입할 수 없어요.\n$daysLeft일 뒤부터 가입할 수 있습니다.';
}

/// 이 학교 이메일로 지금 가입할 수 있는지 미리 확인한다.
///
/// 가입 버튼을 눌렀을 때 계정을 만들기 **전에** 호출한다. 실제 차단은 백엔드의
/// 이메일 인증 관문이 하지만, 미리 확인하지 않으면 계정을 만든 뒤에야 거절돼
/// 되돌리는 과정이 필요해진다.
///
/// 제한에 걸리면 [WithdrawnCooldownException]을 던진다. 네트워크 오류 등으로
/// 확인 자체가 실패하면 **가입을 막지 않는다** — 사전 확인은 어디까지나 안내용이고,
/// 진짜 관문은 서버에 따로 있기 때문에 여기서 막으면 오프라인일 때 멀쩡한
/// 사용자만 가입하지 못한다.
Future<void> ensureSignupAllowed(String email) async {
  http.Response response;
  try {
    response = await postBackend(
      Uri.parse('$kVerifyBackendUrl/api/signup-eligibility'),
      headers: await backendSecurityHeaders(),
      body: jsonEncode({'email': email}),
    );
  } catch (_) {
    return; // 확인 실패는 통과시킨다(서버 관문이 최종 방어선).
  }

  if (response.statusCode >= 400) return;
  final decoded = response.body.isEmpty
      ? const <String, dynamic>{}
      : jsonDecode(response.body) as Map<String, dynamic>;
  if (decoded['allowed'] == false) {
    throw WithdrawnCooldownException(
      (decoded['daysLeft'] as num?)?.toInt() ?? 0,
    );
  }
}

/// 회원 탈퇴를 마무리한다 — 소유 데이터 정리, 재가입 제한 기록, 계정 삭제.
///
/// 계정 삭제까지 백엔드가 하는 이유는 "탈퇴했다는 기록"과 삭제가 반드시 함께
/// 남아야 하기 때문이다(verify_backend/api/withdraw.js 참고). 호출 전에 반드시
/// 재인증을 마쳐야 하며, 본인 소유 데이터도 같은 서버 요청 안에서 정리한다.
///
/// 실패하면 예외를 던진다 — 계정이 남아 있는데 성공으로 처리하면 사용자는
/// 탈퇴된 줄 알고 있다가 다음 실행에서 그대로 로그인된 화면을 보게 된다.
Future<void> withdrawAccount() async {
  final user = FirebaseAuth.instance.currentUser;
  if (user == null) return;

  final response = await postBackend(
    Uri.parse('$kVerifyBackendUrl/api/withdraw'),
    headers: await backendSecurityHeaders(authenticate: true),
  );
  if (response.statusCode >= 400) {
    final decoded = response.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    throw BackendException(decoded['error'] as String? ?? 'unknown');
  }

  // 계정을 서버에서 지웠으므로 이 기기의 로그인 상태도 즉시 끊는다.
  // 예전처럼 클라이언트가 user.delete()를 하면 SDK가 알아서 로그아웃했지만,
  // 서버에서 지우면 토큰이 만료될 때까지 로그인된 것처럼 남아 있는다.
  await FirebaseAuth.instance.signOut();
}
