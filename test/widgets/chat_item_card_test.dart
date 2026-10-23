import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latte/widgets/chat_item_card.dart';

void main() {
  testWidgets('폭 320·큰 글꼴에서도 물건 제목과 상태가 잘리지 않고 게시글을 연다', (tester) async {
    var opened = false;
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(textScaler: TextScaler.linear(2)),
          child: Scaffold(
            body: Align(
              alignment: Alignment.topLeft,
              child: SizedBox(
                width: 320,
                child: ChatItemCard(
                  title: '학생회관에서 주운 아주 긴 이름의 검은색 가죽 지갑',
                  status: '확인 대기',
                  onOpen: () => opened = true,
                ),
              ),
            ),
          ),
        ),
      ),
    );
    expect(tester.takeException(), isNull);
    expect(find.text('확인 대기'), findsOneWidget);
    await tester.tap(find.text('게시글 보기'));
    expect(opened, isTrue);
  });

  testWidgets('삭제된 물건은 제목을 남기고 게시글 보기 동작을 숨긴다', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(
        home: Scaffold(
          body: ChatItemCard(title: '검은색 지갑', status: '게시글 삭제됨'),
        ),
      ),
    );
    expect(find.text('검은색 지갑'), findsOneWidget);
    expect(find.text('게시글 삭제됨'), findsOneWidget);
    expect(find.text('게시글 보기'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
