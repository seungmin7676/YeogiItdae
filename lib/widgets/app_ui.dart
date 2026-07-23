import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ---------------------------------------------------------------------------
/// v3 공통 컨트롤 — 화면마다 제각각 만들던 세그먼트·필터 칩·더 보기 버튼·
/// 섹션 라벨을 하나의 언어로 모았다.
/// ---------------------------------------------------------------------------

/// 연결형 세그먼트 컨트롤 — 회백색 트랙 위에서 선택된 항목만 흰 알약으로
/// 도드라진다. "여러 개 중 정확히 하나"라는 구조가 형태로 읽히도록,
/// 분리된 칩 대신 하나의 트랙으로 묶는다.
class AppSegmented extends StatelessWidget {
  final List<String> labels;
  final int selectedIndex;
  final ValueChanged<int> onChanged;

  const AppSegmented({
    super.key,
    required this.labels,
    required this.selectedIndex,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.all(3),
      decoration: const BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.all(Radius.circular(kRadiusPill)),
      ),
      child: Row(
        children: [
          for (var i = 0; i < labels.length; i++)
            Expanded(
              child: Semantics(
                button: true,
                selected: i == selectedIndex,
                label: labels[i],
                child: GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onChanged(i),
                  child: AnimatedContainer(
                    duration: kMotionFast,
                    curve: Curves.easeOut,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: i == selectedIndex
                          ? AppColors.surface
                          : Colors.transparent,
                      borderRadius: BorderRadius.circular(kRadiusPill),
                      border: Border.all(
                        color: i == selectedIndex
                            ? AppColors.lineStrong
                            : Colors.transparent,
                      ),
                    ),
                    child: Text(
                      labels[i],
                      style: TextStyle(
                        fontSize: 13.5,
                        letterSpacing: -0.2,
                        fontWeight: i == selectedIndex
                            ? FontWeight.w800
                            : FontWeight.w600,
                        color: i == selectedIndex
                            ? AppColors.ink
                            : AppColors.inkMuted,
                      ),
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// 값을 고르는 트리거 칩 — 장소·정렬처럼 "누르면 선택지가 열리는" 필터.
/// 값이 선택되어 있으면(active) 잉크 반전으로 상태가 한눈에 드러난다.
class TriggerChip extends StatelessWidget {
  final String label;
  final IconData? icon;
  final bool active;
  final VoidCallback onTap;

  /// active 상태에서 지우기(해제) 동작이 따로 필요하면 준다.
  final VoidCallback? onClear;

  const TriggerChip({
    super.key,
    required this.label,
    required this.onTap,
    this.icon,
    this.active = false,
    this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final fg = active ? Colors.white : AppColors.inkMuted;
    return Material(
      color: active ? AppColors.ink : AppColors.surface,
      shape: StadiumBorder(
        side: BorderSide(color: active ? AppColors.ink : AppColors.lineStrong),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            icon != null ? 10 : 14,
            0,
            onClear != null && active ? 6 : 12,
            0,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (icon != null) ...[
                Icon(icon, size: 15, color: fg),
                const SizedBox(width: 4),
              ],
              Text(
                label,
                style: TextStyle(
                  fontSize: 13,
                  letterSpacing: -0.2,
                  fontWeight: active ? FontWeight.w700 : FontWeight.w600,
                  color: fg,
                ),
              ),
              if (onClear != null && active) ...[
                const SizedBox(width: 2),
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: onClear,
                  child: Padding(
                    padding: const EdgeInsets.all(4),
                    child: Icon(Icons.close_rounded, size: 14, color: fg),
                  ),
                ),
              ] else if (icon == null) ...[
                const SizedBox(width: 1),
                Icon(Icons.keyboard_arrow_down_rounded, size: 16, color: fg),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 선택형 칩 — 카테고리처럼 "그 자체가 값"인 필터. 선택되면 잉크 반전.
class SelectChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const SelectChip({
    super.key,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Material(
      color: selected ? AppColors.ink : AppColors.surface,
      shape: StadiumBorder(
        side: BorderSide(
          color: selected ? AppColors.ink : AppColors.lineStrong,
        ),
      ),
      child: InkWell(
        customBorder: const StadiumBorder(),
        onTap: onTap,
        child: Container(
          alignment: Alignment.center,
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          child: Text(
            label,
            style: TextStyle(
              fontSize: 13,
              letterSpacing: -0.2,
              fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
              color: selected ? Colors.white : AppColors.inkMuted,
            ),
          ),
        ),
      ),
    );
  }
}

/// 페이지네이션 공통 "더 보기" 버튼. 로딩 중이면 스피너로 바뀌고 중복 탭을
/// 막는다 — 여섯 화면에 복붙되어 있던 패턴을 하나로 모았다.
class LoadMoreButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;

  const LoadMoreButton({
    super.key,
    required this.isLoading,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 16),
      child: Center(
        child: OutlinedButton(
          onPressed: isLoading ? null : onPressed,
          style: OutlinedButton.styleFrom(minimumSize: const Size(120, 40)),
          child: isLoading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Text('더 보기'),
        ),
      ),
    );
  }
}

/// 폼·설정 화면의 섹션 라벨. 작은 대문자형 위계로 그룹을 나눈다.
class SectionLabel extends StatelessWidget {
  final String text;

  const SectionLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Text(
      text,
      style: const TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w700,
        letterSpacing: -0.1,
        color: AppColors.inkMuted,
      ),
    );
  }
}

/// 헤어라인으로 감싼 그룹 표면 — 마이페이지 메뉴, 설정 그룹처럼 관련 항목을
/// 하나의 면으로 묶을 때 쓴다. 그림자 없는 v3의 유일한 "카드".
class GroupSurface extends StatelessWidget {
  final List<Widget> children;

  /// true면 자식 사이에 헤어라인 구분선을 자동으로 넣는다.
  final bool dividers;

  const GroupSurface({super.key, required this.children, this.dividers = true});

  @override
  Widget build(BuildContext context) {
    final items = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      items.add(children[i]);
      if (dividers && i < children.length - 1) {
        items.add(const Divider(indent: 16, endIndent: 16));
      }
    }
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(kRadiusLg),
        border: Border.all(color: AppColors.line),
      ),
      child: Column(children: items),
    );
  }
}
