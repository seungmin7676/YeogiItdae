import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latte/services/backend_http.dart';

void main() {
  test('개발 빌드는 App Check 디버그 공급자를 선택한다', () {
    expect(androidAppCheckProvider(isDebug: true), isA<AndroidDebugProvider>());
    expect(appleAppCheckProvider(isDebug: true), isA<AppleDebugProvider>());
  });

  test('릴리스 빌드는 플랫폼 무결성 공급자를 선택한다', () {
    expect(
      androidAppCheckProvider(isDebug: false),
      isA<AndroidPlayIntegrityProvider>(),
    );
    expect(
      appleAppCheckProvider(isDebug: false),
      isA<AppleAppAttestWithDeviceCheckFallbackProvider>(),
    );
  });

  test('응답이 오면 상태 코드와 본문을 그대로 반환한다', () async {
    final client = MockClient((request) async {
      expect(request.method, 'POST');
      expect(request.body, '{"value":1}');
      return http.Response('{"ok":true}', 200);
    });

    final response = await postBackend(
      Uri.parse('https://example.test/api'),
      body: '{"value":1}',
      client: client,
    );

    expect(response.statusCode, 200);
    expect(response.body, '{"ok":true}');
  });

  test('응답이 끝나지 않으면 제한 시간 예외로 복구한다', () async {
    final client = MockClient((_) => Completer<http.Response>().future);

    await expectLater(
      postBackend(
        Uri.parse('https://example.test/api'),
        client: client,
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<BackendRequestTimeoutException>()),
    );
  });
}
