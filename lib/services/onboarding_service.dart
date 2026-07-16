import 'package:cloud_firestore/cloud_firestore.dart';

/// 기기가 아니라 계정 단위로 기록해야 재설치·다른 기기 로그인 시에도
/// 튜토리얼이 다시 뜨지 않는다.
Future<bool> hasSeenOnboarding(String uid) async {
  final doc = await FirebaseFirestore.instance
      .collection('userSettings')
      .doc(uid)
      .get();
  return doc.data()?['onboardingSeen'] as bool? ?? false;
}

/// 튜토리얼을 봤다고 기록해 다음부터는 다시 뜨지 않게 한다.
Future<void> markOnboardingSeen(String uid) async {
  await FirebaseFirestore.instance.collection('userSettings').doc(uid).set({
    'onboardingSeen': true,
  }, SetOptions(merge: true));
}
