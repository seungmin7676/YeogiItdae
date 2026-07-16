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
    return ClipOval(
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        color: AppColors.primary.withValues(alpha: 0.1),
        child: url != null && url.isNotEmpty
            ? Image.network(
                url,
                width: size,
                height: size,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) =>
                    _defaultIcon(size),
                loadingBuilder: (context, child, progress) =>
                    progress == null ? child : _defaultIcon(size),
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
