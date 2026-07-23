import 'package:flutter/material.dart';

/// ---------------------------------------------------------------------------
/// 디자인 시스템 v3 — "잉크 에디토리얼(Ink Editorial)"
///
/// v2는 회색 배경 위에 흰 카드가 그림자로 떠 있는 구성이었다. 카드·보더·
/// 그림자가 화면마다 겹겹이 쌓여 무거워지는 문제가 있어, v3는 반대 방향으로
/// 간다 — 순백 캔버스 위에서 콘텐츠 자체가 구조가 되는 에디토리얼 톤.
///
///  - 배경과 표면 모두 순백. 구획은 그림자 대신 헤어라인과 여백으로 나눈다.
///  - 목록은 카드가 아니라 풀블리드 행(row) — 스캔 속도와 정보 밀도를 높인다.
///  - 위계는 잉크 스케일의 크기·굵기·명도로만 만든다. 색은 신호에만 쓴다.
///  - 버튼·세그먼트·검색창은 알약(pill), 카드·이미지는 각진 라운드(12~16),
///    시트는 큰 라운드(24) — 역할별로 형태 언어를 구분한다.
///  - 브랜드 블루(#2F6FED)는 primary action과 선택 상태에만. 습득/분실은
///    의미 색(청록/로즈)으로만 구분한다.
/// ---------------------------------------------------------------------------
class AppColors {
  /// 포인트 컬러. 앱 아이콘(#2F6FED)과 맞춘 밝고 또렷한 블루.
  /// "지금 누를 것"(primary action)과 선택 상태에만 쓴다.
  static const Color primary = Color(0xFF2F6FED);

  /// 눌린 상태·강조 배경 등에 쓰는 진한 톤.
  static const Color primaryStrong = Color(0xFF1F55C8);

  /// primary의 아주 옅은 틴트. 선택된 칩/행, 안읽음 표시 배경 등에.
  static const Color primaryMuted = Color(0xFFEDF3FE);

  // 잉크 스케일 — 브랜드와 무관한 중립 색조. 대부분의 텍스트·아이콘이
  // 이 세 단계 안에서 정해진다.
  static const Color ink = Color(0xFF14161A);
  static const Color inkMuted = Color(0xFF5E646D);
  static const Color inkFaint = Color(0xFF9AA1AB);

  /// v3의 캔버스는 순백이다. 배경과 표면을 구분하지 않고, 구획은
  /// 헤어라인(line)과 여백으로 만든다.
  static const Color bg = Colors.white;
  static const Color surface = Colors.white;

  /// 입력 필드·칩·세그먼트 트랙처럼 "채워진 컨트롤"의 바탕.
  static const Color surfaceAlt = Color(0xFFF2F3F5);

  /// 헤어라인. 행 구분·컨트롤 외곽선 등 구조를 만드는 기본 선.
  static const Color line = Color(0xFFE9EBEE);
  static const Color lineStrong = Color(0xFFD8DBE0);

  /// 습득물/분실물처럼 실제로 정보를 전달하는 곳에만 쓰는 색.
  static const Color found = Color(0xFF0B8A74);
  static const Color lost = Color(0xFFDD4A70);

  /// 삭제·탈퇴 등 되돌릴 수 없는 위험 행동 전용.
  static const Color danger = Color(0xFFE0455A);

  /// 보조 강조가 한 군데 더 필요할 때만 쓰는 진한 중립 톤(온보딩 등).
  static const Color accent = Color(0xFF23262C);
}

/// 모서리 반경 — 역할별 형태 언어.
/// 칩·입력은 sm~md, 썸네일·카드는 md~lg, 바텀시트 같은 큰 면은 xl,
/// 버튼·세그먼트·검색창은 [kRadiusPill]로 알약을 만든다.
const double kRadiusSm = 8;
const double kRadiusMd = 12;
const double kRadiusLg = 16;
const double kRadiusXl = 24;
const double kRadiusPill = 999;

/// 페이지 좌우 기본 패딩. 풀블리드 행은 내부 패딩으로 같은 값을 쓴다.
const double kPagePadding = 20;

/// 모션 — 마이크로 인터랙션은 fast, 화면 요소 전환은 standard.
const Duration kMotionFast = Duration(milliseconds: 160);
const Duration kMotionStandard = Duration(milliseconds: 240);

/// v3에서는 카드가 떠 있지 않는다. 예전 kSoftShadow를 쓰던 표면은
/// 그림자 대신 1px 헤어라인 링으로 렌더링된다(블러 0 + 스프레드 1은
/// 둥근 사각형 둘레에 외곽선처럼 그려진다).
const List<BoxShadow> kSoftShadow = [
  BoxShadow(color: AppColors.line, blurRadius: 0, spreadRadius: 1),
];

/// FAB·바텀시트처럼 확실히 위에 있어야 하는 요소에만 남긴 유일한 그림자.
const List<BoxShadow> kElevatedShadow = [
  BoxShadow(
    color: Color(0x2414161A),
    blurRadius: 20,
    spreadRadius: -4,
    offset: Offset(0, 8),
  ),
];

/// 앱 전역에서 공유하는 입력 필드 데코레이션. 채워진 회백색 필드에
/// 포커스 시에만 브랜드 링을 두른다.
InputDecoration appInputDecoration(
  String label, {
  String? hint,
  String? suffixText,
  Widget? prefixIcon,
  Widget? suffixIcon,
  Color? fillColor,
}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(kRadiusMd),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    suffixText: suffixText,
    suffixStyle: const TextStyle(
      color: AppColors.inkMuted,
      fontWeight: FontWeight.w600,
    ),
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: fillColor ?? AppColors.surfaceAlt,
    hintStyle: const TextStyle(color: AppColors.inkFaint),
    labelStyle: const TextStyle(color: AppColors.inkMuted),
    floatingLabelStyle: const TextStyle(
      color: AppColors.primary,
      fontWeight: FontWeight.w700,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: border(Colors.transparent),
    enabledBorder: border(Colors.transparent),
    focusedBorder: border(AppColors.primary, 1.6),
    errorBorder: border(AppColors.danger),
    focusedErrorBorder: border(AppColors.danger, 1.6),
  );
}

/// 검색창 전용 데코레이션 — 라벨 없는 알약 필드. 홈·채팅 목록·선택 시트가
/// 제각각 만들던 검색 InputDecoration을 하나로 모았다.
InputDecoration appSearchDecoration(String hint, {Widget? suffixIcon}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(kRadiusPill),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    hintText: hint,
    hintStyle: const TextStyle(color: AppColors.inkFaint, fontSize: 14.5),
    prefixIcon: const Icon(
      Icons.search_rounded,
      color: AppColors.inkMuted,
      size: 20,
    ),
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: AppColors.surfaceAlt,
    isDense: true,
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
    border: border(Colors.transparent),
    enabledBorder: border(Colors.transparent),
    focusedBorder: border(AppColors.primary, 1.6),
  );
}
