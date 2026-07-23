import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// ---------------------------------------------------------------------------
/// 스켈레톤 로딩
///
/// 빈 화면에 스피너 하나를 띄우는 대신, 실제로 들어올 콘텐츠와 같은 형태의
/// 회색 골격을 먼저 보여준다. 사용자가 "무엇이 로딩되는지"를 미리 알 수 있어
/// 체감 대기 시간이 짧아지고, 데이터가 도착했을 때 레이아웃이 튀지 않는다.
///
/// 셰이더 스윕은 절제된 톤으로만 준다 — line 색을 바탕으로 살짝 밝은 띠가
/// 한 번 지나가는 정도. 시스템에서 애니메이션 축소(reduce motion)를 켰다면
/// 스윕 없이 정적인 골격만 보여준다.
/// ---------------------------------------------------------------------------

const Color _kSkeletonBase = AppColors.line;
const Color _kSkeletonHighlight = Color(0xFFF1F1F3);

/// 자식(불투명한 회색 블록들)을 감싸 밝은 띠가 가로로 지나가는 셰이더를 입힌다.
/// reduce motion이 켜져 있으면 정적인 바탕색만 남긴다.
class _Shimmer extends StatefulWidget {
  final Widget child;

  const _Shimmer({required this.child});

  @override
  State<_Shimmer> createState() => _ShimmerState();
}

class _ShimmerState extends State<_Shimmer>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1350),
  );

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduceMotion) {
      _controller.stop();
      return widget.child;
    }
    if (!_controller.isAnimating) _controller.repeat();

    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        return ShaderMask(
          blendMode: BlendMode.srcATop,
          shaderCallback: (bounds) => LinearGradient(
            begin: Alignment.centerLeft,
            end: Alignment.centerRight,
            colors: const [_kSkeletonBase, _kSkeletonHighlight, _kSkeletonBase],
            stops: const [0.35, 0.5, 0.65],
            transform: _SlideTransform(_controller.value * 2 - 1),
          ).createShader(bounds),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}

/// 그라데이션을 좌우로 밀어 스윕 효과를 만든다. percent -1 → +1 로 흐르는 동안
/// 밝은 띠가 화면 왼쪽 밖에서 오른쪽 밖으로 지나간다.
class _SlideTransform extends GradientTransform {
  final double percent;

  const _SlideTransform(this.percent);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) {
    return Matrix4.translationValues(bounds.width * percent, 0, 0);
  }
}

/// 스켈레톤을 이루는 단일 회색 블록. shimmer가 색을 입혀주므로 여기서는
/// 형태(크기·모서리)만 정의한다.
class SkeletonBox extends StatelessWidget {
  final double? width;
  final double height;
  final double radius;

  const SkeletonBox({
    super.key,
    this.width,
    required this.height,
    this.radius = 6,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: width,
      height: height,
      decoration: BoxDecoration(
        color: _kSkeletonBase,
        borderRadius: BorderRadius.circular(radius),
      ),
    );
  }
}

/// [ItemCard]와 같은 형태의 골격 한 행 — 썸네일, 라벨 줄, 제목, 메타 줄.
/// 실제 행처럼 풀블리드 + 헤어라인 구분으로 그린다.
class _ItemRowSkeleton extends StatelessWidget {
  const _ItemRowSkeleton();

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: kPagePadding,
        vertical: 14,
      ),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.line)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const SkeletonBox(width: 96, height: 96, radius: kRadiusMd),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: const [
                SizedBox(height: 2),
                SkeletonBox(width: 96, height: 14, radius: 6),
                SizedBox(height: 10),
                SkeletonBox(width: double.infinity, height: 16),
                SizedBox(height: 6),
                SkeletonBox(width: 150, height: 16),
                SizedBox(height: 10),
                SkeletonBox(width: 180, height: 12),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// 목록 화면의 최초 로딩 상태. 실제 리스트와 같은 행 형태로 골격을 깔고,
/// 전체에 하나의 shimmer를 입혀 스윕이 화면 전체에서 일관되게 흐르도록 한다.
class ItemListSkeleton extends StatelessWidget {
  final int itemCount;
  final EdgeInsetsGeometry padding;

  const ItemListSkeleton({
    super.key,
    this.itemCount = 6,
    this.padding = EdgeInsets.zero,
  });

  @override
  Widget build(BuildContext context) {
    return _Shimmer(
      child: ListView.builder(
        // 로딩 골격은 스크롤할 필요가 없다 — 넘치는 부분은 자연스럽게 잘리도록.
        physics: const NeverScrollableScrollPhysics(),
        padding: padding,
        itemCount: itemCount,
        itemBuilder: (context, index) => const _ItemRowSkeleton(),
      ),
    );
  }
}
