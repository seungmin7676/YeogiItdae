import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:latte/services/backend_http.dart';
import 'package:latte/services/cloudinary_service.dart';
import 'package:latte/services/notification_outbox.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('업로드 헤더 응답이 없어도 제한 시간 뒤 복구한다', () async {
    await expectLater(
      sendImageRequest(
        http.Request('POST', Uri.parse('https://example.test')),
        client: MockClient((_) => Completer<http.Response>().future),
        timeout: const Duration(milliseconds: 10),
      ),
      throwsA(isA<BackendRequestTimeoutException>()),
    );
  });

  test('업로드 응답 본문이 중간에 멈춰도 제한 시간이 적용된다', () async {
    final body = StreamController<List<int>>();
    try {
      await expectLater(
        sendImageRequest(
          http.Request('POST', Uri.parse('https://example.test')),
          client: MockClient.streaming(
            (_, _) async => http.StreamedResponse(body.stream, 200),
          ),
          timeout: const Duration(milliseconds: 10),
        ),
        throwsA(isA<BackendRequestTimeoutException>()),
      );
    } finally {
      await body.close();
    }
  });

  test('실패한 알림은 재시작 후 복구하고 다른 계정으로 발송하지 않는다', () async {
    var clock = DateTime(2026, 10, 15);
    var uid = 'alice';
    var calls = 0;
    Future<http.Response> send(String _, Map<String, dynamic> _) async {
      calls++;
      return http.Response(
        calls == 1 ? '{}' : '{"ok":true}',
        calls == 1 ? 503 : 200,
      );
    }

    final first = NotificationOutbox(
      currentUid: () => uid,
      send: send,
      now: () => clock,
    );
    await first.enqueue('send-push', {
      'type': 'chat_message',
      'data': {'messageId': 'm1'},
    });
    await first.flush();
    expect(calls, 1);
    clock = clock.add(const Duration(minutes: 1));
    uid = 'bob';
    final restored = NotificationOutbox(
      currentUid: () => uid,
      send: send,
      now: () => clock,
    );
    await restored.flush();
    expect(calls, 1);
    uid = 'alice';
    await restored.flush();
    expect(calls, 2);
    await restored.flush();
    expect(calls, 2);
  });

  test('중복 요청은 한 건으로 보관하고 부분 전송 실패도 재시도한다', () async {
    var clock = DateTime(2026, 10, 15);
    var calls = 0;
    final outbox = NotificationOutbox(
      currentUid: () => 'alice',
      now: () => clock,
      send: (_, _) async =>
          http.Response(++calls == 1 ? '{"failed":1}' : '{"ok":true}', 200),
    );
    final event = {
      'type': 'chat_message',
      'data': {'messageId': 'm1'},
    };
    await Future.wait([
      outbox.enqueue('send-push', event),
      outbox.enqueue('send-push', event),
    ]);
    await outbox.flush();
    expect(calls, 1);
    await outbox.flush();
    expect(calls, 1, reason: '재시도 대기 중 연속 요청을 보내지 않는다');
    clock = clock.add(const Duration(minutes: 1));
    await outbox.flush();
    expect(calls, 2);
  });

  test('삭제된 이벤트의 요청은 반복 발송하지 않는다', () async {
    var calls = 0;
    final outbox = NotificationOutbox(
      currentUid: () => 'alice',
      send: (_, _) async {
        calls++;
        return http.Response('{}', 404);
      },
    );
    await outbox.enqueue('notify-matches', {'itemId': 'removed'});
    await outbox.flush();
    await outbox.flush();
    expect(calls, 1);
  });
}
