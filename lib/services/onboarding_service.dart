import 'package:shared_preferences/shared_preferences.dart';

const String _kOnboardingSeenKey = 'onboarding_seen_v1';

/// 이 기기에서 사용법 튜토리얼을 이미 본 적이 있는지 확인한다.
Future<bool> hasSeenOnboarding() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getBool(_kOnboardingSeenKey) ?? false;
}

/// 튜토리얼을 봤다고 기록해 다음부터는 다시 뜨지 않게 한다.
Future<void> markOnboardingSeen() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.setBool(_kOnboardingSeenKey, true);
}
