import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// 디자인 시스템: 색상 · 그림자 · 공용 입력 필드 스타일
/// 한림대학교 로고(파랑·네이비·틸)에서 뽑은 브랜드 컬러를 기준으로 한다.
/// ---------------------------------------------------------------------------
class AppColors {
  static const Color primary = Color(0xFF005BAC);
  static const Color primaryDark = Color(0xFF002870);
  static const Color accent = Color(0xFF00ADA9);
  static const Color bg = Color(0xFFF4F6FA);
  static const Color surface = Colors.white;
  static const Color ink = Color(0xFF12203D);
  static const Color inkMuted = Color(0xFF64748B);
  static const Color line = Color(0xFFE2E6EF);
  static const Color foundBg = Color(0xFFE0F5F4);
  static const Color foundFg = Color(0xFF00726F);
  static const Color lostBg = Color(0xFFFBEBEC);
  static const Color lostFg = Color(0xFFB93B4B);
  static const Color danger = Color(0xFFB93B4B);
}

/// 카드/시트에 쓰는 부드러운 그림자.
const List<BoxShadow> kSoftShadow = [
  BoxShadow(color: Color(0x141B2B4D), blurRadius: 20, offset: Offset(0, 8)),
];

/// 브랜드 그라데이션 (로고·강조 영역). 로고의 파랑에서 네이비로 이어지는 톤.
const LinearGradient kBrandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF005BAC), Color(0xFF002870)],
);

/// 앱 전역에서 공유하는 입력 필드 데코레이션.
InputDecoration appInputDecoration(
  String label, {
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: AppColors.surface,
    hintStyle: const TextStyle(color: Color(0xFFB4B7C4)),
    labelStyle: const TextStyle(color: AppColors.inkMuted),
    floatingLabelStyle: const TextStyle(
      color: AppColors.primary,
      fontWeight: FontWeight.w600,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: border(AppColors.line),
    enabledBorder: border(AppColors.line),
    focusedBorder: border(AppColors.primary, 1.6),
    errorBorder: border(AppColors.lostFg),
    focusedErrorBorder: border(AppColors.lostFg, 1.6),
  );
}
