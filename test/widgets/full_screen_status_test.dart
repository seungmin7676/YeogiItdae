import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latte/widgets/full_screen_status.dart';

Widget _wrap(Widget child, {double textScale = 1, double width = 320}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(
        size: Size(width, 568),
        textScaler: TextScaler.linear(textScale),
      ),
      child: Scaffold(body: child),
    ),
  );
}

void main() {
  testWidgets('로딩 작업과 진행 상태를 스크린리더에 알린다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        const FullScreenStatus.loading(
          title: '프로필을 준비하고 있어요',
          message: '잠시만 기다려주세요.',
        ),
      ),
    );

    expect(find.text('프로필을 준비하고 있어요'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel(RegExp('불러오는 중')), findsOneWidget);
  });

  testWidgets('오류 상태에서 재시도 동작을 제공한다', (tester) async {
    var retryCount = 0;
    await tester.pumpWidget(
      _wrap(
        FullScreenStatus(
          title: '정보를 불러오지 못했어요',
          message: '입력한 정보는 변경되지 않았어요.',
          actionLabel: '다시 시도',
          onAction: () => retryCount++,
        ),
      ),
    );

    await tester.tap(find.widgetWithText(OutlinedButton, '다시 시도'));

    expect(retryCount, 1);
  });

  testWidgets('작은 화면과 2배 글꼴에서도 내용이 잘리지 않는다', (tester) async {
    await tester.pumpWidget(
      _wrap(
        FullScreenStatus(
          title: '로그인 상태를 확인하지 못했어요',
          message: '네트워크 연결을 확인한 뒤 다시 시도해주세요.',
          actionLabel: '다시 시도',
          onAction: () {},
        ),
        textScale: 2,
      ),
    );

    expect(tester.takeException(), isNull);
    expect(find.text('로그인 상태를 확인하지 못했어요'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });
}
