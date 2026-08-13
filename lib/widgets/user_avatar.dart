import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 사용자 프로필 사진. [photoUrl]이 있으면 그 사진을, 없거나 불러오지
/// 못하면 사람 모양 기본 아이콘을 보여준다.
class UserAvatar extends StatelessWidget {
  final String nickname;
  final String? photoUrl;
  final double size;

  const UserAvatar({
    super.key,
    required this.nickname,
    this.photoUrl,
    this.size = 44,
  });

  @override
  Widget build(BuildContext context) {
    final url = photoUrl;
    // 프로필 사진 원본(최대 800px)을 34~64dp 원형 안에 그대로 디코딩하면
    // 채팅 목록처럼 아바타가 여러 개 뜨는 화면에서 메모리가 낭비된다.
    final decodeSize = (size * MediaQuery.devicePixelRatioOf(context)).round();
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        color: AppColors.primaryMuted,
        child: url != null && url.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                memCacheWidth: decodeSize,
                memCacheHeight: decodeSize,
                errorWidget: (context, url, error) => _defaultIcon(size),
                placeholder: (context, url) => _defaultIcon(size),
              )
            : _defaultIcon(size),
      ),
    );
  }

  Widget _defaultIcon(double size) {
    return Icon(
      Icons.person_rounded,
      color: AppColors.primary,
      size: size * 0.6,
      semanticLabel: '$nickname 프로필 사진',
    );
  }
}
