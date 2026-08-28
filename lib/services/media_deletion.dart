import 'dart:convert';

import 'backend_exception.dart';
import 'backend_http.dart';

Future<void> deleteUploadedMedia(Iterable<String> urls) async {
  final unique = urls.where((url) => url.isNotEmpty).toSet().toList();
  if (unique.isEmpty) return;
  final response = await postBackend(
    Uri.parse('$kVerifyBackendUrl/api/delete-media'),
    headers: await backendSecurityHeaders(authenticate: true),
    body: jsonEncode({'urls': unique}),
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
