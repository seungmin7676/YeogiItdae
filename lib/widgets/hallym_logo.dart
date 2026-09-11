import 'package:flutter/material.dart';

/// 한림대학교 공식 심볼 마크.
class HallymLogo extends StatelessWidget {
  static const double _aspectRatio = 468 / 224;

  /// 표시 높이. 공식 심볼의 가로세로 비율은 그대로 유지한다.
  final double size;

  const HallymLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/hallym_logo.png',
      width: size * _aspectRatio,
      height: size,
      fit: BoxFit.contain,
      semanticLabel: '한림대학교 로고',
    );
  }
}
