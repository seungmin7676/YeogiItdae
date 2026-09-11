import 'package:firebase_auth/firebase_auth.dart';

/// 관리자 계정 이메일. 신고 검토·처리 권한을 가진 전시 운영 계정들이다.
///
/// 앱 UI 노출 여부는 이 목록으로 판단하고, 실제 권한(신고 문서 열람, 게시글
/// 숨김/삭제 등)은 Firestore 보안 규칙(firestore.rules)에서 같은 목록을
/// 다시 검증한다. 클라이언트 판단은 우회 가능하므로 규칙이 최종 방어선이다.
const Set<String> kAdminEmails = {
  'admin1@hallym.ac.kr',
  'admin2@hallym.ac.kr',
  'admin3@hallym.ac.kr',
  'admin4@hallym.ac.kr',
  'admin5@hallym.ac.kr',
};

/// 주어진 이메일이 관리자 이메일인지(대소문자 무시) 확인한다.
bool isAdminEmail(String? email) =>
    email != null && kAdminEmails.contains(email.toLowerCase());

/// 현재 로그인한 사용자가 관리자인지 확인한다.
bool isCurrentUserAdmin() =>
    isAdminEmail(FirebaseAuth.instance.currentUser?.email);
