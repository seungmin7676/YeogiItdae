import 'package:flutter_test/flutter_test.dart';
import 'package:latte/services/admin.dart';

void main() {
  test('전시 관리자 다섯 계정만 관리자 이메일로 판정한다', () {
    expect(kAdminEmails, hasLength(5));
    for (var index = 1; index <= 5; index += 1) {
      expect(isAdminEmail('admin$index@hallym.ac.kr'), isTrue);
    }
    expect(isAdminEmail('ADMIN1@HALLYM.AC.KR'), isTrue);
    expect(isAdminEmail('admin6@hallym.ac.kr'), isFalse);
    expect(isAdminEmail('student@hallym.ac.kr'), isFalse);
    expect(isAdminEmail(null), isFalse);
  });
}
