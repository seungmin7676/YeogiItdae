import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 목록/스트림이 비어있거나 에러일 때 보여주는 상태 안내.
///
/// v3에서는 "왜 비었는지"와 "다음에 뭘 할 수 있는지"를 함께 말한다 —
/// [title]로 상황을, [text]로 이유·안내를, [actionLabel]/[onAction]으로
/// 바로 이어질 행동(글 등록, 필터 해제, 다시 시도)을 제공한다.
class FeedMessage extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? title;
  final String? actionLabel;
  final VoidCallback? onAction;

  const FeedMessage({
    super.key,
    required this.icon,
    required this.text,
    this.title,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 72,
              height: 72,
              decoration: const BoxDecoration(
                color: AppColors.surfaceAlt,
                shape: BoxShape.circle,
              ),
              alignment: Alignment.center,
              child: Icon(icon, size: 32, color: AppColors.inkFaint),
            ),
            const SizedBox(height: 18),
            if (title != null) ...[
              Text(
                title!,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: AppColors.ink,
                  fontSize: 16.5,
                  fontWeight: FontWeight.w800,
                  letterSpacing: -0.3,
                ),
              ),
              const SizedBox(height: 6),
            ],
            Text(
              text,
              textAlign: TextAlign.center,
              style: const TextStyle(
                color: AppColors.inkMuted,
                fontSize: 14,
                height: 1.55,
                fontWeight: FontWeight.w500,
              ),
            ),
            if (actionLabel != null && onAction != null) ...[
              const SizedBox(height: 18),
              OutlinedButton(
                onPressed: onAction,
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(140, 44),
                  foregroundColor: AppColors.ink,
                ),
                child: Text(actionLabel!),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
