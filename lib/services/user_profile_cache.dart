import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 다른 사용자의 공개 프로필(닉네임·사진).
@immutable
class UserPublicProfile {
  final String? nickname;
  final String? photoUrl;

  const UserPublicProfile({this.nickname, this.photoUrl});

  static const empty = UserPublicProfile();
}

/// 공개 프로필을 앱 세션 동안 캐시한다.
///
/// 예전에는 채팅 목록·알림 목록·차단 관리가 **행마다** userPublicProfiles
/// 실시간 리스너를 하나씩 만들었다. 채팅방이 50개면 리스너도 50개고, 스크롤로
/// 행이 붙었다 떨어질 때마다 구독이 새로 붙었다 떨어졌다.
///
/// 닉네임·프로필 사진은 자주 바뀌지 않으므로 실시간 구독 대신 uid별로 한 번만
/// 읽어 캐시한다. 같은 uid를 여러 행이 동시에 요청해도 Future 하나를 공유하므로
/// 읽기도 한 번만 일어난다. 대신 다른 사람이 방금 바꾼 사진은 앱을 다시 켤
/// 때까지 반영되지 않는데, 리스너 수십 개를 유지하는 값으로는 비싸다고 봤다.
/// 본인이 바꾼 경우에는 [invalidate]로 즉시 반영한다.
class UserProfileCache {
  UserProfileCache._();

  static final Map<String, Future<UserPublicProfile>> _cache = {};

  static Future<UserPublicProfile> get(String uid) {
    if (uid.isEmpty) return Future.value(UserPublicProfile.empty);
    return _cache.putIfAbsent(uid, () => _fetch(uid));
  }

  static Future<UserPublicProfile> _fetch(String uid) async {
    try {
      final doc = await FirebaseFirestore.instance
          .collection('userPublicProfiles')
          .doc(uid)
          .get();
      final data = doc.data();
      if (data == null) return UserPublicProfile.empty;
      return UserPublicProfile(
        nickname: data['nickname'] as String?,
        photoUrl: data['photoUrl'] as String?,
      );
    } catch (e) {
      // 못 읽으면 호출한 쪽이 준비해둔 대체 닉네임을 쓴다. 실패를 캐시에
      // 남기면 이후 계속 빈 값이 나오므로 캐시에서 지워 다음에 다시 시도한다.
      _cache.remove(uid);
      debugPrint('userPublicProfiles/$uid 조회 실패: $e');
      return UserPublicProfile.empty;
    }
  }

  /// 본인이 닉네임·사진을 바꿨을 때처럼 값이 확실히 달라진 경우에 호출한다.
  static void invalidate(String uid) => _cache.remove(uid);

  /// 로그아웃 시 호출해 다음 계정이 이전 세션의 값을 보지 않게 한다.
  static void clear() => _cache.clear();

  @visibleForTesting
  static void debugSeed(String uid, UserPublicProfile profile) {
    _cache[uid] = Future.value(profile);
  }
}
