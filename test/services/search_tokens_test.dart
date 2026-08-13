import 'package:flutter_test/flutter_test.dart';
import 'package:latte/services/search_tokens.dart';

/// 서버 검색 토큰 규칙 테스트.
///
/// 여기서 확인하는 동작은 verify_backend/test/search.test.js의 동일한
/// 케이스와 **결과가 같아야 한다**(앱이 새 글에 쓰는 토큰과 백필이 기존 글에
/// 채우는 토큰이 어긋나면 백필된 글은 검색되지 않는다).
void main() {
  group('buildSearchTokens', () {
    test('제목을 두 글자 단위로 잘라 토큰을 만든다', () {
      expect(buildSearchTokens('백팩', ''), ['백팩']);
      expect(buildSearchTokens('검은백팩', ''), ['검은', '은백', '백팩']);
    });

    test('공백을 없애고 이어붙이므로 띄어쓰기가 달라도 같은 토큰이 나온다', () {
      expect(buildSearchTokens('아이폰 15', ''), buildSearchTokens('아이폰15', ''));
    });

    test('대소문자를 구분하지 않는다', () {
      expect(
        buildSearchTokens('AirPods', ''),
        buildSearchTokens('airpods', ''),
      );
    });

    test('제목과 설명을 함께 토큰으로 만든다', () {
      final tokens = buildSearchTokens('지갑', '검은색 가죽');
      expect(tokens, contains('지갑'));
      expect(tokens, contains('가죽'));
    });

    test('중복 토큰은 한 번만 넣는다', () {
      final tokens = buildSearchTokens('가방가방', '');
      expect(tokens.length, tokens.toSet().length);
    });

    test('내용이 없으면 빈 목록이다', () {
      expect(buildSearchTokens('', ''), isEmpty);
      expect(buildSearchTokens('   ', ''), isEmpty);
    });

    test('한 글자뿐이면 그 글자를 토큰으로 넣는다', () {
      expect(buildSearchTokens('폰', ''), ['폰']);
    });

    test('아주 긴 설명이 있어도 토큰 수가 상한을 넘지 않는다', () {
      final tokens = buildSearchTokens('제목', '가나다라마바사' * 500);
      expect(tokens.length, lessThanOrEqualTo(kMaxSearchTokens));
    });
  });

  group('searchTokenFor', () {
    test('검색어의 앞 두 글자를 조회 토큰으로 쓴다', () {
      expect(searchTokenFor('백팩'), '백팩');
      expect(searchTokenFor('검은색 백팩'), '검은');
    });

    test('공백만 다른 검색어는 같은 토큰이 된다', () {
      expect(searchTokenFor('아이폰 15'), searchTokenFor('아이폰15'));
    });

    test('두 글자 미만이면 서버 필터를 쓰지 않도록 null을 돌려준다', () {
      expect(searchTokenFor('폰'), isNull);
      expect(searchTokenFor(''), isNull);
      expect(searchTokenFor('   '), isNull);
    });

    test('검색어의 조회 토큰은 그 글의 토큰 목록에 실제로 들어 있다', () {
      // 서버 후보 조회(arrayContains)가 성립하려면 이 관계가 항상 참이어야 한다.
      final tokens = buildSearchTokens('검은색 백팩을 주웠어요', '학생회관 1층');
      for (final query in ['검은색', '백팩', '주웠', '학생회관', '1층']) {
        expect(
          tokens,
          contains(searchTokenFor(query)),
          reason: '"$query" 검색이 이 글을 후보로 잡지 못한다',
        );
      }
    });
  });

  group('matchesSearchQuery', () {
    test('제목이나 설명 어디에 있어도 찾는다', () {
      expect(
        matchesSearchQuery('가죽', title: '지갑', description: '검은색 가죽'),
        isTrue,
      );
    });

    test('부분 문자열로 걸린다(가방 → 책가방)', () {
      expect(
        matchesSearchQuery('가방', title: '책가방을 주웠어요', description: ''),
        isTrue,
      );
    });

    test('띄어쓰기가 달라도 걸린다', () {
      expect(
        matchesSearchQuery('아이폰15', title: '아이폰 15 분실', description: ''),
        isTrue,
      );
      expect(
        matchesSearchQuery('아이폰 15', title: '아이폰15 분실', description: ''),
        isTrue,
      );
    });

    test('관계없는 검색어는 걸리지 않는다', () {
      expect(
        matchesSearchQuery('우산', title: '검은 지갑', description: '가죽'),
        isFalse,
      );
    });

    test('빈 검색어는 모두 통과시킨다', () {
      expect(matchesSearchQuery('', title: '지갑', description: ''), isTrue);
    });
  });
}
