import 'package:flutter_test/flutter_test.dart';
import 'package:latte/services/user_profile_cache.dart';

/// 공개 프로필 캐시 회귀 테스트.
///
/// 고친 문제: 채팅 목록·알림·차단 관리가 **행마다** userPublicProfiles
/// 실시간 리스너를 붙여, 방이 50개면 리스너도 50개였다. 캐시의 핵심 계약은
/// "같은 uid는 한 번만 읽는다"이므로 그것을 확인한다.
void main() {
  setUp(UserProfileCache.clear);

  test('같은 uid를 여러 번 요청해도 조회는 한 번만 일어난다', () async {
    UserProfileCache.debugSeed(
      'uid1',
      const UserPublicProfile(nickname: '홍길동', photoUrl: 'https://x/a.jpg'),
    );

    // 같은 Future 인스턴스를 돌려줘야 여러 행이 동시에 요청해도 읽기가
    // 한 번만 나간다(FutureBuilder도 다시 조회하지 않는다).
    final first = UserProfileCache.get('uid1');
    final second = UserProfileCache.get('uid1');
    expect(identical(first, second), isTrue);
    expect((await first).nickname, '홍길동');
  });

  test('uid가 다르면 각각 따로 캐시한다', () async {
    UserProfileCache.debugSeed('uid1', const UserPublicProfile(nickname: 'A'));
    UserProfileCache.debugSeed('uid2', const UserPublicProfile(nickname: 'B'));

    expect((await UserProfileCache.get('uid1')).nickname, 'A');
    expect((await UserProfileCache.get('uid2')).nickname, 'B');
  });

  test('빈 uid는 조회하지 않고 빈 프로필을 돌려준다', () async {
    expect((await UserProfileCache.get('')).nickname, isNull);
  });

  test('invalidate하면 그 uid만 캐시에서 빠진다', () async {
    UserProfileCache.debugSeed('uid1', const UserPublicProfile(nickname: 'A'));
    UserProfileCache.debugSeed('uid2', const UserPublicProfile(nickname: 'B'));

    final before = UserProfileCache.get('uid1');
    UserProfileCache.invalidate('uid1');

    // 지운 쪽은 새 Future(= 다시 조회), 안 지운 쪽은 그대로여야 한다.
    UserProfileCache.debugSeed('uid1', const UserPublicProfile(nickname: 'A2'));
    expect(identical(UserProfileCache.get('uid1'), before), isFalse);
    expect((await UserProfileCache.get('uid1')).nickname, 'A2');
    expect((await UserProfileCache.get('uid2')).nickname, 'B');
  });

  test('clear하면 로그아웃 후 이전 계정 값이 남지 않는다', () async {
    UserProfileCache.debugSeed('uid1', const UserPublicProfile(nickname: 'A'));
    final before = UserProfileCache.get('uid1');

    UserProfileCache.clear();

    UserProfileCache.debugSeed('uid1', const UserPublicProfile(nickname: 'A2'));
    expect(identical(UserProfileCache.get('uid1'), before), isFalse);
    expect((await UserProfileCache.get('uid1')).nickname, 'A2');
  });
}
