import 'package:firebase_analytics/firebase_analytics.dart';

/// 앱 전역에서 공유하는 Analytics 인스턴스. `logSignUp` 등은 Analytics 표준
/// 이벤트 이름(Firebase 콘솔에서 바로 대시보드로 보이는 이름)을 그대로
/// 써서, 화면마다 이벤트 이름을 따로 정하다 생기는 실수를 줄인다.
final FirebaseAnalytics analytics = FirebaseAnalytics.instance;

Future<void> logSignUp() => analytics.logSignUp(signUpMethod: 'email');

Future<void> logLogin() => analytics.logLogin(loginMethod: 'email');

Future<void> logItemRegistered({
  required String category,
  required String type,
}) => analytics.logEvent(
  name: 'item_registered',
  parameters: {'category': category, 'type': type},
);

Future<void> logChatStarted() => analytics.logEvent(name: 'chat_started');
