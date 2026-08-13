import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latte/services/item_queries.dart';
import 'package:latte/services/search_tokens.dart';

/// 서버 검색(searchTokens) 회귀 테스트.
///
/// 고친 문제: 검색이 "이미 불러온 페이지" 안에서만 동작해서, 한참 전에 올라온
/// 글은 "더 보기"를 여러 번 눌러야만 찾을 수 있었다. 이제 등록 시 저장한
/// 2-gram 토큰으로 서버에서 전체 컬렉션을 조회한다.
void main() {
  late FakeFirebaseFirestore firestore;
  late CollectionReference<Map<String, dynamic>> items;

  Future<void> add({
    required String title,
    String description = '',
    String type = 'found',
    String category = '기타',
    String location = '(1) 공학관',
    required int index,
  }) async {
    await items.add({
      'title': title,
      'description': description,
      'location': location,
      'locationDetail': '',
      'type': type,
      'category': category,
      'authorUid': 'author1',
      'authorNickname': '테스터',
      'resolved': false,
      'imageUrls': <String>[],
      'searchTokens': buildSearchTokens(title, description),
      'reportCount': 0,
      'viewCount': index,
      'createdAt': Timestamp.fromDate(
        DateTime(2026, 1, 1).add(Duration(minutes: index)),
      ),
    });
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    items = firestore.collection('items');
  });

  Future<List<String>> search(
    String query, {
    bool sortByPopular = false,
    int limit = kInitialPageLimit,
  }) async {
    final snap = await buildFeedQuery(
      collection: items,
      typeFilter: 0,
      category: kAllFilterLabel,
      location: kAllFilterLabel,
      sortByPopular: sortByPopular,
      limit: limit,
      searchToken: searchTokenFor(query),
    ).get();
    // 화면과 같은 순서: 서버가 좁혀준 후보에 최종 판정을 적용한다.
    return snap.docs
        .map((d) => d.data())
        .where(
          (d) => matchesSearchQuery(
            query,
            title: d['title'] as String,
            description: d['description'] as String,
          ),
        )
        .map((d) => d['title'] as String)
        .toList();
  }

  test('첫 페이지 밖(100번째 이전)에 있는 글도 검색으로 찾는다', () async {
    // 찾으려는 글을 가장 오래된 자리에 두고, 그 위에 관련 없는 글 120개를 쌓는다.
    // 예전 방식(불러온 20개 안에서만 필터)이었다면 절대 나오지 않았을 상황이다.
    await add(title: '검은색 가죽 지갑', index: 0);
    for (var i = 1; i <= 120; i++) {
      await add(title: '우산 $i', index: i);
    }

    expect(await search('지갑'), ['검은색 가죽 지갑']);
  });

  test('부분 문자열로도 찾는다(가방 → 책가방)', () async {
    await add(title: '책가방 주웠어요', index: 0);
    await add(title: '우산', index: 1);

    expect(await search('가방'), ['책가방 주웠어요']);
  });

  test('띄어쓰기가 달라도 찾는다', () async {
    await add(title: '아이폰15 프로 분실', index: 0);

    expect(await search('아이폰 15'), ['아이폰15 프로 분실']);
  });

  test('설명에만 있는 단어도 찾는다', () async {
    await add(title: '지갑', description: '학생회관 1층 북카페에서 주웠어요', index: 0);
    await add(title: '우산', index: 1);

    expect(await search('북카페'), ['지갑']);
  });

  test('토큰만 걸리고 실제로는 포함하지 않는 후보는 최종 판정에서 걸러진다', () async {
    // '검은색 백팩'의 토큰에는 어절을 넘나드는 '색백'이 들어간다. 후보로는
    // 잡히더라도 최종 판정에서 빠져야 한다.
    await add(title: '검은색 백팩', index: 0);

    final tokens = buildSearchTokens('검은색 백팩', '');
    expect(tokens, contains('색백'));
    expect(await search('색백팩입니다'), isEmpty);
  });

  test('관계없는 검색어는 아무것도 반환하지 않는다', () async {
    await add(title: '검은색 지갑', index: 0);

    expect(await search('노트북'), isEmpty);
  });

  test('조회순 정렬에서도 검색이 동작한다', () async {
    await add(title: '지갑 A', index: 1);
    await add(title: '지갑 B', index: 9);

    expect(await search('지갑', sortByPopular: true), ['지갑 B', '지갑 A']);
  });

  test('한 글자 검색어는 서버 토큰 없이 조회한다(불러온 목록 안에서만 거름)', () async {
    await add(title: '지갑', index: 0);
    await add(title: '우산', index: 1);

    expect(searchTokenFor('갑'), isNull);
    // 토큰이 없으면 buildFeedQuery는 평소의 목록 쿼리와 같아야 한다.
    final snap = await buildFeedQuery(
      collection: items,
      typeFilter: 0,
      category: kAllFilterLabel,
      location: kAllFilterLabel,
      sortByPopular: false,
      limit: kInitialPageLimit,
      searchToken: searchTokenFor('갑'),
    ).get();
    expect(snap.docs.length, 2);
  });

  test('검색 토큰이 없는 예전 글은 검색에 걸리지 않는다(백필이 필요한 이유)', () async {
    // 백필 전 상태를 재현한다 — searchTokens 필드가 없는 문서.
    await items.add({
      'title': '검은색 지갑',
      'description': '',
      'location': '(1) 공학관',
      'locationDetail': '',
      'type': 'found',
      'category': '기타',
      'authorUid': 'author1',
      'authorNickname': '테스터',
      'resolved': false,
      'imageUrls': <String>[],
      'viewCount': 0,
      'createdAt': Timestamp.fromDate(DateTime(2026, 1, 1)),
    });

    expect(await search('지갑'), isEmpty);
  });
}
