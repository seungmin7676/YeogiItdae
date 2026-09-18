import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latte/screens/login_screen.dart';
import 'package:latte/screens/signup_screen.dart';
import 'package:latte/theme/app_theme.dart';

Widget _app({double textScale = 1}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: const LoginScreen(),
  );
}

void main() {
  testWidgets('로그인 폼은 화면 높이의 가운데에 배치된다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final formCenter = tester.getRect(find.byType(Form)).center.dy;
    expect(formCenter, closeTo(844 / 2, 1));
    expect(tester.takeException(), isNull);
  });

  testWidgets('회원가입을 선택하면 별도 화면으로 이동한다', (tester) async {
    await tester.pumpWidget(_app());
    await tester.enterText(find.byType(TextFormField).first, '20261234');

    await tester.tap(find.text('계정이 없으신가요? 회원가입'));
    await tester.pumpAndSettle();

    expect(find.byType(SignupScreen), findsOneWidget);
    expect(find.widgetWithText(AppBar, '회원가입'), findsOneWidget);
    final signupEmailField = tester.widget<TextFormField>(
      find.byType(TextFormField).first,
    );
    expect(signupEmailField.controller?.text, '20261234');
    expect(tester.takeException(), isNull);
  });

  testWidgets('넓은 화면에서 로그인 폼이 읽기 좋은 폭을 유지한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app());
    await tester.pumpAndSettle();

    final emailField = find.byType(TextFormField).first;
    expect(tester.getSize(emailField).width, lessThanOrEqualTo(kFormMaxWidth));
    expect(tester.takeException(), isNull);
  });

  testWidgets('320px 화면과 2배 글꼴에서도 로그인 CTA에 접근할 수 있다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(textScale: 2));
    await tester.pumpAndSettle();

    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(ElevatedButton, '로그인'), findsOneWidget);
    await tester.ensureVisible(find.widgetWithText(ElevatedButton, '로그인'));
    expect(tester.takeException(), isNull);
  });
}
