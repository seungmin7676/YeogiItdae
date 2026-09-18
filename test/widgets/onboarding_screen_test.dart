import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latte/screens/onboarding_screen.dart';

Widget _app({
  double textScale = 1,
  bool isReplay = false,
  VoidCallback? onFinished,
}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: OnboardingScreen(
      uid: 'test-user',
      isReplay: isReplay,
      onFinished: onFinished ?? () {},
    ),
  );
}

void main() {
  testWidgets('다음 버튼으로 독립된 기능 안내 페이지를 넘긴다', (tester) async {
    await tester.pumpWidget(_app());
    expect(find.text('WELCOME'), findsOneWidget);
    expect(find.text('교내 전용'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-next-button')));
    await tester.pumpAndSettle();

    expect(find.text('FIND'), findsOneWidget);
    expect(find.text('전자기기'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('작은 화면과 2배 글꼴에서도 진행 버튼에 접근할 수 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(textScale: 2));
    await tester.pumpAndSettle();

    expect(
      find.byKey(const ValueKey('onboarding-next-button')),
      findsOneWidget,
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('다시 보기에서는 계정 설정 항목 없이 바로 닫을 수 있다', (tester) async {
    var finished = false;
    await tester.pumpWidget(
      _app(isReplay: true, onFinished: () => finished = true),
    );

    expect(find.text('다음부터 보지 않기'), findsNothing);
    expect(find.text('닫기'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('onboarding-close-button')));
    await tester.pump();

    expect(finished, isTrue);
    expect(tester.takeException(), isNull);
  });
}
