import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class UserAvatar extends StatelessWidget {
  final String nickname;
  final double size;

  const UserAvatar({super.key, required this.nickname, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final trimmed = nickname.trim();
    final letter = trimmed.isNotEmpty ? trimmed.characters.first : '?';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: kBrandGradient,
        shape: BoxShape.circle,
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}
