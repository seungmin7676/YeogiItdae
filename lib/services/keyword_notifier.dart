import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'backend_exception.dart';
import 'backend_http.dart';

/// 새 글이 등록됐으니 키워드·카테고리 구독자에게 알림을 보내달라고 백엔드에
/// 요청한다.
///
/// 예전에는 글을 올리는 클라이언트가 savedSearches 컬렉션 **전체**를 직접
/// 읽어 매칭했다. 그러려면 보안 규칙에서 savedSearches를 모든 로그인 사용자에게
/// 열어줘야 했고, 그 결과 아무 학생이나 다른 사람이 저장해둔 검색 키워드를
/// uid와 함께 전부 열람할 수 있었다. 또 글 하나 등록할 때마다 읽는 문서 수가
/// 사용자 수만큼 늘어났다.
///
/// Admin SDK를 가진 백엔드가 대신 매칭하면 savedSearches를 본인만 읽도록
/// 잠글 수 있고, 클라이언트의 읽기 비용도 0이 된다.
///
/// 알림 발송 실패는 글 등록 자체를 되돌릴 만한 일이 아니므로 조용히 삼킨다
/// (호출한 쪽은 결과를 기다리지 않아도 된다).
Future<void> notifyKeywordMatches({required String itemId}) async {
  try {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;
    await postBackend(
      Uri.parse('$kVerifyBackendUrl/api/notify-matches'),
      headers: await backendSecurityHeaders(authenticate: true),
      body: jsonEncode({'itemId': itemId}),
    );
  } catch (_) {
    // 구독 알림이 안 나가도 글은 정상 등록된 상태다.
  }
}
