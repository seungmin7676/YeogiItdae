import 'package:flutter/material.dart';

import '../services/user_profile_cache.dart';
import 'user_avatar.dart';

/// uid로 공개 프로필을 캐시에서 읽어 아바타를 그린다.
///
/// 아직 못 읽었거나 사진이 없으면 [fallbackNickname] 기준의 기본 아바타를
/// 보여준다 — 스피너를 끼우면 목록을 스크롤할 때마다 깜빡여 더 산만하다.
class UserProfileAvatar extends StatelessWidget {
  final String uid;
  final String fallbackNickname;
  final double size;

  const UserProfileAvatar({
    super.key,
    required this.uid,
    required this.fallbackNickname,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserPublicProfile>(
      future: UserProfileCache.get(uid),
      builder: (context, snapshot) {
        final profile = snapshot.data;
        return UserAvatar(
          nickname: profile?.nickname ?? fallbackNickname,
          photoUrl: profile?.photoUrl,
          size: size,
        );
      },
    );
  }
}

/// uid로 최신 닉네임을 캐시에서 읽어 표시한다. 못 읽으면 문서에 저장돼 있던
/// 그 시점 닉네임([fallbackNickname])을 그대로 쓴다.
class UserProfileNickname extends StatelessWidget {
  final String uid;
  final String fallbackNickname;
  final TextStyle? style;

  /// 닉네임을 문장 안에 끼워 넣을 때 쓴다(예: '$nickname님이 채팅을 걸었어요').
  final String Function(String nickname)? format;

  const UserProfileNickname({
    super.key,
    required this.uid,
    required this.fallbackNickname,
    this.style,
    this.format,
  });

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<UserPublicProfile>(
      future: UserProfileCache.get(uid),
      builder: (context, snapshot) {
        final nickname = snapshot.data?.nickname ?? fallbackNickname;
        return Text(format?.call(nickname) ?? nickname, style: style);
      },
    );
  }
}
