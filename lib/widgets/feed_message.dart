import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 목록/스트림이 비어있거나 에러일 때 보여주는 안내 문구.
class FeedMessage extends StatelessWidget {
  final IconData icon;
  final String text;

  const FeedMessage({super.key, required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: const Color(0xFFC7CAD6)),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
