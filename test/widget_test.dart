// 이 앱의 화면 대부분은 Firebase(Auth/Firestore)에 의존하기 때문에,
// 별도의 Firebase 목(mock) 설정 없이도 안전하게 테스트할 수 있는
// 순수 위젯/함수 단위로 스모크 테스트를 작성한다.

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:latte/theme/app_theme.dart';
import 'package:latte/widgets/user_avatar.dart';

void main() {
  group('UserAvatar', () {
    testWidgets('photoUrl이 없으면 기본 사람 아이콘을 표시한다', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Material(child: UserAvatar(nickname: '테스트봇')),
        ),
      );

      expect(find.byIcon(Icons.person_rounded), findsOneWidget);
    });

    testWidgets('photoUrl이 있으면 이미지를 표시한다', (WidgetTester tester) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Material(
            child: UserAvatar(
              nickname: '테스트봇',
              photoUrl: 'https://example.com/photo.png',
            ),
          ),
        ),
      );

      expect(find.byType(Image), findsOneWidget);
    });
  });

  group('appInputDecoration', () {
    test('라벨과 힌트 텍스트를 그대로 담는다', () {
      final decoration = appInputDecoration('학교 이메일', hint: '학번@hallym.ac.kr');

      expect(decoration.labelText, '학교 이메일');
      expect(decoration.hintText, '학번@hallym.ac.kr');
      expect(decoration.filled, true);
    });
  });
}
