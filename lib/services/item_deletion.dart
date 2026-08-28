import 'dart:convert';

import 'backend_exception.dart';
import 'backend_http.dart';

/// 게시글 문서와 연결된 Cloudinary 원본을 서버에서 함께 삭제한다.
Future<void> deleteItemOnServer(String itemId) async {
  final response = await postBackend(
    Uri.parse('$kVerifyBackendUrl/api/delete-item'),
    headers: await backendSecurityHeaders(authenticate: true),
    body: jsonEncode({'itemId': itemId}),
  );
  if (response.statusCode >= 400) {
    final decoded = response.body.isEmpty
        ? const <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    throw BackendException(
      decoded['error'] as String? ?? 'unknown',
      data: decoded,
    );
  }
}
