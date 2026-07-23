import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latte/models/lost_found_item.dart';
import 'package:latte/widgets/app_ui.dart';
import 'package:latte/widgets/feed_message.dart';
import 'package:latte/widgets/item_card.dart';

/// 작은 화면 폭에서 v3 공통 컴포넌트가 overflow 없이 렌더링되는지와,
/// 상태·콜백이 의도대로 동작하는지 확인한다.
Widget _wrap(Widget child, {double width = 320}) {
  return MaterialApp(
    home: Scaffold(
      body: Center(
        child: SizedBox(width: width, child: child),
      ),
    ),
  );
}

LostFoundItem _item({
  String title = '검은색 가죽 지갑을 학생회관 1층에서 주웠습니다',
  bool resolved = false,
  int viewCount = 25,
}) {
  return LostFoundItem(
    id: 'test',
    title: title,
    location: '(9) Campus Life Center',
    type: ItemType.found,
    category: '지갑/카드/현금',
    authorUid: 'uid',
    authorNickname: '아주아주긴닉네임입니다',
    resolved: resolved,
    viewCount: viewCount,
    createdAt: DateTime.now().subtract(const Duration(minutes: 5)),
  );
}

void main() {
  group('ItemCard', () {
    testWidgets('작은 폭(320)에서 긴 제목·메타가 overflow 없이 그려진다', (tester) async {
      await tester.pumpWidget(_wrap(ItemCard(item: _item(), onTap: () {})));
      expect(find.text('습득물'), findsOneWidget);
      expect(find.textContaining('검은색 가죽 지갑'), findsOneWidget);
      // 조회수 임계값(20) 이상이므로 인기 배지가 붙는다.
      expect(find.text('인기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('선택 모드에서 체크 표시가 나타나고 탭 콜백이 동작한다', (tester) async {
      var tapped = false;
      await tester.pumpWidget(
        _wrap(
          ItemCard(
            item: _item(),
            selectionMode: true,
            selected: true,
            onTap: () => tapped = true,
          ),
        ),
      );
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
      await tester.tap(find.byType(ItemCard));
      expect(tapped, isTrue);
    });

    testWidgets('거래완료 글은 배지를 표시한다', (tester) async {
      await tester.pumpWidget(
        _wrap(
          ItemCard(item: _item(resolved: true, viewCount: 0), onTap: () {}),
        ),
      );
      expect(find.text('거래완료'), findsOneWidget);
    });
  });

  group('AppSegmented', () {
    testWidgets('탭하면 선택 인덱스 콜백이 호출된다', (tester) async {
      int? selected;
      await tester.pumpWidget(
        _wrap(
          AppSegmented(
            labels: const ['전체', '습득물', '분실물'],
            selectedIndex: 0,
            onChanged: (i) => selected = i,
          ),
        ),
      );
      await tester.tap(find.text('분실물'));
      expect(selected, 2);
      expect(tester.takeException(), isNull);
    });
  });

  group('FeedMessage', () {
    testWidgets('제목·본문·액션 버튼을 표시하고 콜백이 동작한다', (tester) async {
      var pressed = false;
      await tester.pumpWidget(
        _wrap(
          FeedMessage(
            icon: Icons.inbox_outlined,
            title: '아직 등록된 글이 없어요',
            text: '첫 게시글을 등록해보세요.',
            actionLabel: '글 등록하기',
            onAction: () => pressed = true,
          ),
        ),
      );
      expect(find.text('아직 등록된 글이 없어요'), findsOneWidget);
      await tester.tap(find.text('글 등록하기'));
      expect(pressed, isTrue);
    });

    testWidgets('액션이 없으면 버튼을 그리지 않는다', (tester) async {
      await tester.pumpWidget(
        _wrap(const FeedMessage(icon: Icons.inbox_outlined, text: '알림이 없어요.')),
      );
      expect(find.byType(OutlinedButton), findsNothing);
    });
  });

  group('TriggerChip / SelectChip', () {
    testWidgets('active 상태에서 해제(onClear)가 별도로 동작한다', (tester) async {
      var cleared = false;
      var opened = false;
      await tester.pumpWidget(
        _wrap(
          SizedBox(
            height: 36,
            child: Row(
              children: [
                TriggerChip(
                  label: '(1) 공학관',
                  icon: Icons.place_outlined,
                  active: true,
                  onTap: () => opened = true,
                  onClear: () => cleared = true,
                ),
              ],
            ),
          ),
        ),
      );
      await tester.tap(find.byIcon(Icons.close_rounded));
      expect(cleared, isTrue);
      expect(opened, isFalse);
      await tester.tap(find.text('(1) 공학관'));
      expect(opened, isTrue);
    });

    testWidgets('SelectChip은 Wrap 안(높이 제약 없음)에서도 그려진다', (tester) async {
      await tester.pumpWidget(
        _wrap(
          Wrap(
            children: [
              SelectChip(label: '전자기기', selected: true, onTap: () {}),
              SelectChip(label: '지갑/카드/현금', selected: false, onTap: () {}),
            ],
          ),
        ),
      );
      expect(find.text('전자기기'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
