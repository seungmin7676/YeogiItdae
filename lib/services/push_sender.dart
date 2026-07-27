import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;

import 'backend_exception.dart';

/// 이벤트를 일으킨 클라이언트가 호출해 수신자에게 푸시를 보내도록 백엔드에
/// 요청한다. 실제 발송·필터링(차단·알림설정)·죽은 토큰 정리는 Vercel
/// 백엔드(/api/send-push)의 Admin SDK가 담당한다.
///
/// 발송 실패는 주 동작(메시지 전송·글 등록 등)을 막으면 안 되므로 내부에서
/// 삼킨다. 화면 코드는 결과를 기다릴 필요 없이 호출만 하면 된다.
///
/// [recipientUid]가 null이면 관리자 대상 알림(report_received, bug_report)으로
/// 간주되어 백엔드가 관리자 계정으로 라우팅한다.
Future<void> sendPush({
  String? recipientUid,
  required String type,
  required String title,
  required String body,
  Map<String, dynamic> data = const {},
}) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    final idToken = await user.getIdToken();
    await http.post(
      Uri.parse('$kVerifyBackendUrl/api/send-push'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode({
        'recipientUid': ?recipientUid,
        'type': type,
        'title': title,
        'body': body,
        'data': data,
      }),
    );
  } catch (_) {
    // 푸시 발송 실패는 조용히 넘어간다.
  }
}
