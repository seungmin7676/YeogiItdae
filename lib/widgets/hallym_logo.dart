import 'package:flutter/material.dart';

/// 한림대학교 공식 로고 마크.
class HallymLogo extends StatelessWidget {
  final double size;

  const HallymLogo({super.key, this.size = 32});

  @override
  Widget build(BuildContext context) {
    return Image.asset(
      'assets/branding/hallym_logo.png',
      width: size,
      height: size,
      semanticLabel: '한림대학교 로고',
    );
  }
}
