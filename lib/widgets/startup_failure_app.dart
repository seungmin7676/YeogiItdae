import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class StartupLoadingApp extends StatelessWidget {
  const StartupLoadingApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: const Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(child: Center(child: _StartupLoadingContent())),
      ),
    );
  }
}

class _StartupLoadingContent extends StatelessWidget {
  const _StartupLoadingContent();

  @override
  Widget build(BuildContext context) {
    return Semantics(
      container: true,
      label: '앱을 시작하는 중',
      liveRegion: true,
      excludeSemantics: true,
      child: const Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            '여기있대!',
            style: TextStyle(
              color: AppColors.ink,
              fontSize: 28,
              fontWeight: FontWeight.w800,
              letterSpacing: -0.8,
            ),
          ),
          SizedBox(height: 24),
          SizedBox.square(
            dimension: 24,
            child: CircularProgressIndicator(
              strokeWidth: 2.5,
              color: AppColors.primary,
            ),
          ),
        ],
      ),
    );
  }
}

class StartupFailureApp extends StatefulWidget {
  final Future<void> Function() onRetry;

  const StartupFailureApp({super.key, required this.onRetry});

  @override
  State<StartupFailureApp> createState() => _StartupFailureAppState();
}

class _StartupFailureAppState extends State<StartupFailureApp> {
  bool _isRetrying = false;

  Future<void> _retry() async {
    if (_isRetrying) return;
    setState(() => _isRetrying = true);
    try {
      await widget.onRetry();
    } finally {
      if (mounted) setState(() => _isRetrying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      home: Scaffold(
        backgroundColor: AppColors.bg,
        body: SafeArea(
          child: Center(
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 420),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(
                      Icons.cloud_off_outlined,
                      size: 48,
                      color: AppColors.inkMuted,
                    ),
                    const SizedBox(height: 20),
                    const Text(
                      '앱을 시작할 수 없어요',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.ink,
                        fontSize: 20,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                    const SizedBox(height: 10),
                    const Text(
                      '네트워크 연결을 확인한 뒤 다시 시도해주세요.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 14,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
                    SizedBox(
                      width: double.infinity,
                      height: 52,
                      child: ElevatedButton(
                        onPressed: _isRetrying ? null : _retry,
                        style: ElevatedButton.styleFrom(
                          backgroundColor: AppColors.primary,
                          foregroundColor: Colors.white,
                          disabledBackgroundColor: AppColors.surfaceAlt,
                          shape: const StadiumBorder(),
                        ),
                        child: _isRetrying
                            ? const SizedBox.square(
                                dimension: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: AppColors.inkMuted,
                                ),
                              )
                            : const Text('다시 시도'),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
