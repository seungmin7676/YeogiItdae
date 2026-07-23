import 'package:cloud_firestore/cloud_firestore.dart';

/// 예외를 사용자에게 보여줄 한국어 메시지로 변환한다. `Exception.toString()`을
/// 그대로 스낵바에 띄우면 `[cloud_firestore/permission-denied] ...` 같은
/// 내부 오류 코드가 노출되므로, 알려진 Firebase 예외 코드는 의미 있는
/// 문구로 바꾸고 나머지는 일반적인 안내 문구로 대체한다.
String friendlyErrorMessage(Object error) {
  if (error is FirebaseException) {
    switch (error.code) {
      case 'permission-denied':
        return '권한이 없어 처리할 수 없어요.';
      case 'not-found':
        return '이미 삭제되었거나 존재하지 않는 항목이에요.';
      case 'unavailable':
      case 'deadline-exceeded':
        return '네트워크가 불안정해요. 잠시 후 다시 시도해주세요.';
      case 'resource-exhausted':
        return '요청이 많아 잠시 처리할 수 없어요. 잠시 후 다시 시도해주세요.';
      case 'unauthenticated':
        return '로그인이 필요해요.';
      case 'already-exists':
        return '이미 존재하는 항목이에요.';
      case 'cancelled':
        return '요청이 취소됐어요.';
    }
  }
  return '문제가 발생했어요. 잠시 후 다시 시도해주세요.';
}
