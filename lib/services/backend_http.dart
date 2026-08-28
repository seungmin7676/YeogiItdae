import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

const Duration kBackendRequestTimeout = Duration(seconds: 30);
const bool kAppCheckEnabled = bool.fromEnvironment(
  'APP_CHECK_ENABLED',
  defaultValue: true,
);
Future<void>? _appCheckActivation;

class BackendRequestTimeoutException implements Exception {
  const BackendRequestTimeoutException();
}

AndroidAppCheckProvider androidAppCheckProvider({required bool isDebug}) =>
    isDebug
    ? const AndroidDebugProvider()
    : const AndroidPlayIntegrityProvider();

AppleAppCheckProvider appleAppCheckProvider({required bool isDebug}) => isDebug
    ? const AppleDebugProvider()
    : const AppleAppAttestWithDeviceCheckFallbackProvider();

/// App Check 활성화를 한 번만 수행한다. 앱 시작 직후 사용자가 백엔드 기능을
/// 빠르게 눌러도 활성화와 토큰 요청이 경주하지 않도록 실제 API 호출도 이 Future를
/// 기다린다. 실패한 Future는 비워 다음 요청에서 복구를 재시도할 수 있게 한다.
Future<void> ensureAppCheckActivated() async {
  // Play Console을 사용하지 않는 교내 전시용 GitHub APK는 빌드 시
  // APP_CHECK_ENABLED=false를 전달한다. 이 경우 Play Integrity 토큰 요청을
  // 만들지 않고, 서버의 인증·rate limit만으로 제한된 전시를 운영한다.
  if (!kAppCheckEnabled) return;

  final existing = _appCheckActivation;
  if (existing != null) {
    await existing;
    return;
  }

  final attempt = FirebaseAppCheck.instance.activate(
    // 에뮬레이터·개발 빌드는 Firebase에 등록한 디버그 토큰을 사용한다.
    // 전시용 release APK는 Play Integrity/App Attest를 유지해 우회 토큰이
    // 배포 파일에 들어가지 않도록 빌드 모드에서 자동 분리한다.
    providerAndroid: androidAppCheckProvider(isDebug: kDebugMode),
    providerApple: appleAppCheckProvider(isDebug: kDebugMode),
  );
  _appCheckActivation = attempt;
  try {
    await attempt;
  } catch (_) {
    if (identical(_appCheckActivation, attempt)) _appCheckActivation = null;
    rethrow;
  }
}

/// Vercel API 호출에 공통으로 붙이는 앱 무결성·사용자 인증 헤더.
Future<Map<String, String>> backendSecurityHeaders({
  bool authenticate = false,
}) async {
  final headers = <String, String>{'Content-Type': 'application/json'};
  if (kAppCheckEnabled) {
    try {
      await ensureAppCheckActivated();
      final appCheckToken = await FirebaseAppCheck.instance.getToken();
      if (appCheckToken != null && appCheckToken.toString().isNotEmpty) {
        headers['X-Firebase-AppCheck'] = appCheckToken.toString();
      }
    } catch (_) {
      // 서버가 운영 환경에서 fail-closed로 최종 판정한다. 여기서는 플랫폼 미지원
      // 등의 원래 예외보다 API의 일관된 app-check-failed 응답을 받게 둔다.
    }
  }
  if (authenticate) {
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    if (idToken != null) headers['Authorization'] = 'Bearer $idToken';
  }
  return headers;
}

/// 백엔드 POST 요청이 무기한 로딩 상태로 남지 않도록 공통 제한 시간을 적용한다.
///
/// 테스트나 장기 연결을 공유하는 호출자는 [client]를 주입할 수 있다. 주입하지
/// 않은 경우 이 함수가 만든 client는 성공·실패·시간 초과 모두에서 닫힌다.
Future<http.Response> postBackend(
  Uri uri, {
  Map<String, String>? headers,
  Object? body,
  http.Client? client,
  Duration timeout = kBackendRequestTimeout,
}) async {
  final requestClient = client ?? http.Client();
  try {
    return await requestClient
        .post(uri, headers: headers, body: body)
        .timeout(timeout);
  } on TimeoutException {
    throw const BackendRequestTimeoutException();
  } finally {
    if (client == null) requestClient.close();
  }
}
