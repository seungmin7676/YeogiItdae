import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latte/widgets/startup_failure_app.dart';

void main() {
  testWidgets('Firebase 초기화 전에도 즉시 시작 화면을 표시한다', (tester) async {
    await tester.pumpWidget(const StartupLoadingApp());

    expect(find.text('여기있대!'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.bySemanticsLabel('앱을 시작하는 중'), findsOneWidget);
  });

  testWidgets('시작 실패 원인 대신 복구 안내와 재시도 버튼을 보여준다', (tester) async {
    await tester.pumpWidget(StartupFailureApp(onRetry: () async {}));

    expect(find.text('앱을 시작할 수 없어요'), findsOneWidget);
    expect(find.text('네트워크 연결을 확인한 뒤 다시 시도해주세요.'), findsOneWidget);
    expect(find.text('다시 시도'), findsOneWidget);
  });

  testWidgets('재시도 처리 중 연속 탭을 막고 완료 후 다시 활성화한다', (tester) async {
    final completer = Completer<void>();
    var calls = 0;
    await tester.pumpWidget(
      StartupFailureApp(
        onRetry: () {
          calls += 1;
          return completer.future;
        },
      ),
    );

    await tester.tap(find.text('다시 시도'));
    await tester.pump();
    await tester.tap(find.byType(ElevatedButton));
    expect(calls, 1);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);

    completer.complete();
    await tester.pump();
    expect(find.text('다시 시도'), findsOneWidget);
    expect(
      tester.widget<ElevatedButton>(find.byType(ElevatedButton)).onPressed,
      isNotNull,
    );
  });
}
