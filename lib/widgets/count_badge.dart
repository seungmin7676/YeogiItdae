import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 아이폰 알림 배지 스타일의 작은 빨간 숫자 배지.
class CountBadge extends StatelessWidget {
  final int count;

  const CountBadge({super.key, required this.count});

  @override
  Widget build(BuildContext context) {
    // Container의 alignment(그리고 Center/Align)는 "부모가 bounded 제약을
    // 주면 그 크기만큼 확장한 뒤 안에서 정렬"하는 동작이라, ListTile의
    // trailing처럼 느슨하지만 유한한 폭 제약 안에서는 배지가 타일 전체
    // 폭까지 늘어나 버린다("Trailing widget consumes the entire tile
    // width" 에러의 원인). 정렬용 위젯을 아예 쓰지 않고 padding만으로
    // 내용을 감싸야 내용 크기(+ minWidth) 그대로 유지된다.
    return Container(
      height: 16,
      constraints: const BoxConstraints(minWidth: 16),
      padding: const EdgeInsets.symmetric(horizontal: 3),
      decoration: BoxDecoration(
        color: AppColors.danger,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(
        count > 99 ? '99+' : '$count',
        style: const TextStyle(
          color: Colors.white,
          fontSize: 10,
          fontWeight: FontWeight.w700,
          height: 1.0,
        ),
      ),
    );
  }
}

/// 아이콘 오른쪽 위에 [CountBadge]를 겹쳐 보여준다.
/// count가 0 이하면 배지 없이 아이콘만 그대로 보여준다.
class IconWithCountBadge extends StatelessWidget {
  final Widget icon;
  final int count;

  const IconWithCountBadge({
    super.key,
    required this.icon,
    required this.count,
  });

  @override
  Widget build(BuildContext context) {
    // count가 0↔양수로 바뀔 때마다 위젯 트리 구조 자체(Icon ↔ Stack)가
    // 바뀌면, 이 위젯이 마우스 호버를 추적하는 조상(NavigationBar,
    // IconButton 등) 안에 있을 때 렌더 오브젝트가 매번 폐기·재생성되면서
    // 웹에서 MouseTracker 어설션이 깨지는 문제가 있었다. 항상 같은 Stack
    // 구조를 유지하고 배지 유무만 조건부로 넣어 트리 모양을 안정시킨다.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        icon,
        if (count > 0)
          Positioned(right: -6, top: -4, child: CountBadge(count: count)),
      ],
    );
  }
}
