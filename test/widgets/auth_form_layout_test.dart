import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latte/screens/complete_profile_screen.dart';
import 'package:latte/screens/password_reset_screen.dart';
import 'package:latte/theme/app_theme.dart';

Widget _app(Widget home, {double textScale = 1}) {
  return MaterialApp(
    builder: (context, child) => MediaQuery(
      data: MediaQuery.of(
        context,
      ).copyWith(textScaler: TextScaler.linear(textScale)),
      child: child!,
    ),
    home: home,
  );
}

void main() {
  testWidgets('비밀번호 재설정 폼은 넓은 화면에서도 최대 폭을 유지한다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(1200, 900));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(_app(const PasswordResetScreen()));
    await tester.pumpAndSettle();

    expect(
      tester.getSize(find.byType(TextFormField).first).width,
      lessThanOrEqualTo(kFormMaxWidth),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('프로필 복구 폼은 320px와 2배 글꼴에서도 스크롤 가능하다', (tester) async {
    await tester.binding.setSurfaceSize(const Size(320, 568));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(
      _app(
        const CompleteProfileScreen(uid: 'uid', nickname: '닉네임'),
        textScale: 2,
      ),
    );
    await tester.pumpAndSettle();

    expect(find.widgetWithText(ElevatedButton, '저장하고 시작하기'), findsOneWidget);
    await tester.ensureVisible(
      find.widgetWithText(ElevatedButton, '저장하고 시작하기'),
    );
    expect(tester.takeException(), isNull);
  });
}
