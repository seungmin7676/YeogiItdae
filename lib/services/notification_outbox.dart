import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/widgets.dart';
import 'package:http/http.dart' as http;
import 'package:shared_preferences/shared_preferences.dart';

import 'backend_exception.dart';
import 'backend_http.dart';

/// 사용자별 실패 요청을 재시작 이후에도 보존한다. 서버의 이벤트 멱등 키와
/// 함께 사용해 응답 유실에 따른 재시도가 같은 알림을 중복 발송하지 않게 한다.
class NotificationOutbox {
  NotificationOutbox({
    required this.currentUid,
    required this.send,
    DateTime Function()? now,
  }) : now = now ?? DateTime.now;

  static const _key = 'notification_outbox_v1';
  final String? Function() currentUid;
  final Future<http.Response> Function(String path, Map<String, dynamic> body)
  send;
  final DateTime Function() now;
  Future<void> _storage = Future.value();
  bool _flushing = false;

  Future<void> _mutate(void Function(List<Map<String, dynamic>>) action) {
    final operation = _storage.then((_) async {
      final preferences = await SharedPreferences.getInstance();
      List<Map<String, dynamic>> requests;
      try {
        requests = (jsonDecode(preferences.getString(_key) ?? '[]') as List)
            .whereType<Map>()
            .map((entry) => Map<String, dynamic>.from(entry))
            .toList();
      } catch (_) {
        requests = [];
      }
      requests.removeWhere(
        (entry) =>
            entry['expiresAt'] is! int ||
            (entry['expiresAt'] as int) <= now().millisecondsSinceEpoch,
      );
      action(requests);
      await preferences.setString(_key, jsonEncode(requests));
    });
    _storage = operation.catchError((_) {});
    return operation;
  }

  Future<void> enqueue(String path, Map<String, dynamic> body) async {
    final uid = currentUid();
    if (uid == null) return;
    final id = base64UrlEncode(utf8.encode('$uid:$path:${jsonEncode(body)}'));
    await _mutate((requests) {
      if (requests.any((entry) => entry['id'] == id)) return;
      requests.add({
        'id': id,
        'uid': uid,
        'path': path,
        'body': body,
        'attempts': 0,
        'nextAt': 0,
        'expiresAt': now()
            .add(const Duration(hours: 24))
            .millisecondsSinceEpoch,
      });
    });
  }

  Future<void> flush() async {
    if (_flushing) return;
    final uid = currentUid();
    if (uid == null) return;
    _flushing = true;
    try {
      final pending = <Map<String, dynamic>>[];
      await _mutate((requests) {
        pending.addAll(
          requests
              .where(
                (entry) =>
                    entry['uid'] == uid &&
                    (entry['nextAt'] as int? ?? 0) <=
                        now().millisecondsSinceEpoch,
              )
              .take(12),
        );
      });
      for (final entry in pending) {
        if (currentUid() != uid) break;
        var completed = false;
        try {
          final response = await send(
            entry['path'] as String,
            Map<String, dynamic>.from(entry['body'] as Map),
          );
          // 401은 토큰 갱신 후 재시도, 429·5xx는 서버 복구 후 재시도한다.
          completed = response.statusCode >= 200 && response.statusCode < 300;
          if (completed && response.body.isNotEmpty) {
            final body = jsonDecode(response.body);
            if (body is Map &&
                ((body['failed'] as num? ?? 0) > 0 ||
                    body['retryable'] == true)) {
              completed = false;
            }
          }
          if (response.statusCode >= 400 &&
              response.statusCode < 500 &&
              ![401, 408, 429].contains(response.statusCode)) {
            completed = true;
          }
        } catch (_) {
          // 네트워크 오류도 같은 계정의 다음 실행·복귀 때 이어서 처리한다.
        }
        await _mutate((requests) {
          if (completed) {
            requests.removeWhere((request) => request['id'] == entry['id']);
          } else {
            for (final request in requests.where(
              (request) => request['id'] == entry['id'],
            )) {
              final attempts = (request['attempts'] as int? ?? 0) + 1;
              request['attempts'] = attempts;
              final seconds = (5 * (1 << attempts.clamp(0, 6))).clamp(10, 300);
              request['nextAt'] = now()
                  .add(Duration(seconds: seconds))
                  .millisecondsSinceEpoch;
            }
          }
        });
      }
    } finally {
      _flushing = false;
    }
  }
}

class NotificationDelivery with WidgetsBindingObserver {
  NotificationDelivery._();
  static final instance = NotificationDelivery._();
  late final queue = NotificationOutbox(
    currentUid: () => FirebaseAuth.instance.currentUser?.uid,
    send: (path, body) async {
      final sender = FirebaseAuth.instance.currentUser;
      if (sender == null) throw StateError('signed-out');
      final headers = await backendSecurityHeaders().timeout(
        const Duration(seconds: 10),
      );
      final token = await sender.getIdToken().timeout(
        const Duration(seconds: 10),
      );
      if (token == null ||
          FirebaseAuth.instance.currentUser?.uid != sender.uid) {
        throw StateError('account-changed');
      }
      headers['Authorization'] = 'Bearer $token';
      return postBackend(
        Uri.parse('$kVerifyBackendUrl/api/$path'),
        headers: headers,
        body: jsonEncode(body),
      );
    },
  );
  Timer? _timer;

  void start() {
    if (_timer != null) return;
    WidgetsBinding.instance.addObserver(this);
    FirebaseAuth.instance.authStateChanges().listen((_) => _flush());
    _timer = Timer.periodic(const Duration(seconds: 15), (_) => _flush());
    _flush();
  }

  Future<void> enqueue(String path, Map<String, dynamic> body) async {
    try {
      await queue.enqueue(path, body);
      _flush();
    } catch (_) {
      // 디스크가 가득 차도 주 동작을 실패 처리하지 않고 즉시 발송을 시도한다.
      try {
        await queue.send(path, body);
      } catch (_) {}
    }
  }

  void _flush() {
    unawaited(queue.flush().catchError((_) {}));
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _flush();
  }
}
