import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 앱 진입 단계처럼 아직 보여줄 기존 콘텐츠가 없는 화면의 상태 안내.
///
/// 목록 안에서 사용하는 [FeedMessage]와 달리 SafeArea, 스크롤, 콘텐츠 폭
/// 제한을 직접 제공한다. 따라서 작은 화면이나 큰 글꼴에서도 오류 설명과
/// 재시도 버튼이 화면 밖으로 잘리지 않는다.
class FullScreenStatus extends StatelessWidget {
  final String title;
  final String message;
  final IconData? icon;
  final bool loading;
  final String? actionLabel;
  final VoidCallback? onAction;

  const FullScreenStatus({
    super.key,
    required this.title,
    required this.message,
    this.icon,
    this.loading = false,
    this.actionLabel,
    this.onAction,
  });

  const FullScreenStatus.loading({
    super.key,
    required this.title,
    required this.message,
  }) : icon = null,
       loading = true,
       actionLabel = null,
       onAction = null;

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(32),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 380),
            child: Semantics(
              container: true,
              liveRegion: true,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  SizedBox.square(
                    dimension: 64,
                    child: DecoratedBox(
                      decoration: const BoxDecoration(
                        color: AppColors.surfaceAlt,
                        shape: BoxShape.circle,
                      ),
                      child: Center(
                        child: loading
                            ? const SizedBox.square(
                                dimension: 28,
                                child: CircularProgressIndicator(
                                  color: AppColors.primary,
                                  strokeWidth: 2.5,
                                  semanticsLabel: '불러오는 중',
                                ),
                              )
                            : Icon(
                                icon ?? Icons.error_outline_rounded,
                                size: 30,
                                color: AppColors.inkMuted,
                              ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  Text(
                    title,
                    textAlign: TextAlign.center,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  Text(
                    message,
                    textAlign: TextAlign.center,
                    style: Theme.of(
                      context,
                    ).textTheme.bodyMedium?.copyWith(color: AppColors.inkMuted),
                  ),
                  if (actionLabel != null && onAction != null) ...[
                    const SizedBox(height: 24),
                    OutlinedButton(
                      onPressed: onAction,
                      style: OutlinedButton.styleFrom(
                        minimumSize: const Size(160, 48),
                      ),
                      child: Text(actionLabel!),
                    ),
                  ],
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
