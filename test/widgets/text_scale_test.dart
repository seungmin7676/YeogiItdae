import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latte/theme/app_theme.dart';
import 'package:latte/widgets/app_ui.dart';

/// 시스템 글자 확대(접근성 설정)에서 높이가 고정된 컨트롤이 잘리지 않는지
/// 확인한다. 고친 버그: 세그먼트·필터 칩 줄의 높이가 상수(40/36)로 못 박혀
/// 있어 배율을 올리면 라벨이 위아래로 잘렸고, 긴 라벨은 두 줄로 접히면서
/// 트랙 높이를 넘겼다.
Widget _wrap(Widget child, {double textScale = 1.0, double width = 320}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(textScaler: TextScaler.linear(textScale)),
      child: Scaffold(
        body: Center(
          child: SizedBox(width: width, child: child),
        ),
      ),
    ),
  );
}

void main() {
  group('scaledControlHeight', () {
    testWidgets('기본 배율에서는 기준 높이를 그대로 쓴다', (tester) async {
      late double height;
      await tester.pumpWidget(
        _wrap(
          Builder(
            builder: (context) {
              height = scaledControlHeight(context, 40);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(height, 40);
    });

    testWidgets('글자를 키우면 높이도 함께 커진다', (tester) async {
      late double height;
      await tester.pumpWidget(
        _wrap(
          textScale: 1.3,
          Builder(
            builder: (context) {
              height = scaledControlHeight(context, 40);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(height, greaterThan(40));
    });

    testWidgets('배율이 아무리 커도 기준의 1.3배를 넘지 않는다', (tester) async {
      late double height;
      await tester.pumpWidget(
        _wrap(
          textScale: 3.0,
          Builder(
            builder: (context) {
              height = scaledControlHeight(context, 40);
              return const SizedBox.shrink();
            },
          ),
        ),
      );
      expect(height, closeTo(52, 0.001));
    });
  });

  group('AppSegmented', () {
    testWidgets('작은 폭에서 긴 라벨이 overflow 없이 한 줄로 그려진다', (tester) async {
      await tester.pumpWidget(
        _wrap(
          AppSegmented(
            labels: const ['습득 · 주웠어요', '분실 · 잃어버렸어요'],
            selectedIndex: 0,
            onChanged: (_) {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      final text = tester.widget<Text>(find.text('분실 · 잃어버렸어요'));
      expect(text.maxLines, 1);
      expect(text.overflow, TextOverflow.ellipsis);
    });

    testWidgets('글자 배율 1.3에서도 좁은 화면에서 overflow가 나지 않는다', (tester) async {
      await tester.pumpWidget(
        _wrap(
          textScale: 1.3,
          AppSegmented(
            labels: const ['습득 · 주웠어요', '분실 · 잃어버렸어요'],
            selectedIndex: 1,
            onChanged: (_) {},
          ),
        ),
      );
      expect(tester.takeException(), isNull);
    });
  });

  group('SegmentedToggle', () {
    testWidgets('글자 배율 1.3에서도 overflow 없이 그려지고 선택이 동작한다', (tester) async {
      var value = false;
      await tester.pumpWidget(
        _wrap(
          textScale: 1.3,
          SegmentedToggle(
            leftLabel: '최신순',
            rightLabel: '조회순',
            value: false,
            onChanged: (v) => value = v,
          ),
        ),
      );
      expect(tester.takeException(), isNull);
      await tester.tap(find.text('조회순'));
      expect(value, isTrue);
    });
  });

  group('LoadMoreButton', () {
    testWidgets('로딩 중에는 스피너를 보여주고 다시 눌리지 않는다', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(LoadMoreButton(isLoading: true, onPressed: () => taps++)),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);
      expect(find.text('더 보기'), findsNothing);
      await tester.tap(find.byType(OutlinedButton));
      expect(taps, 0);
    });

    testWidgets('로딩이 끝나면 다시 누를 수 있다', (tester) async {
      var taps = 0;
      await tester.pumpWidget(
        _wrap(LoadMoreButton(isLoading: false, onPressed: () => taps++)),
      );
      expect(find.text('더 보기'), findsOneWidget);
      await tester.tap(find.byType(OutlinedButton));
      expect(taps, 1);
    });
  });
}
