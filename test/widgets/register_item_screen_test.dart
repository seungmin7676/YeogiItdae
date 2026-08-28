import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latte/screens/register_item_screen.dart';
import 'package:latte/theme/app_theme.dart';

Widget _app({double textScale = 1}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: const RegisterItemScreen(),
  );
}

void main() {
  testWidgets('넓은 화면에서 등록 폼과 CTA가 과도하게 늘어나지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    expect(find.byType(TextField).first.hitTestable(), findsOneWidget);
    expect(
      tester.getSize(find.byType(TextField).first).width,
      lessThanOrEqualTo(kFormMaxWidth),
    );
    expect(
      tester.getSize(find.byType(ElevatedButton)).width,
      lessThanOrEqualTo(kFormMaxWidth),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px 화면과 2배 글꼴에서도 필수 안내와 CTA가 잘리지 않는다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(textScale: 2));
    await tester.pumpAndSettle();

    await tester.ensureVisible(find.byType(TextField).first);
    await tester.pumpAndSettle();
    expect(find.byType(TextField).first.hitTestable(), findsOneWidget);
    expect(find.text('물건 이름을 입력해주세요'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
