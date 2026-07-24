import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latte/services/item_queries.dart';

/// 목록 화면의 필터가 Firestore 쿼리에 실려 나가는지 검증한다.
///
/// 회귀 대상: 예전에는 필터를 클라이언트에서 걸러서, limit(20)이 "전체 글
/// 상위 20개"를 세는 바람에 필터를 켜면 그중 일부만 남아 목록이 몇 개
/// 안 나왔다. 아래 테스트들은 필터를 켠 상태에서도 첫 페이지가 꽉 차는지를
/// 확인한다.
void main() {
  late FakeFirebaseFirestore firestore;
  late CollectionReference<Map<String, dynamic>> items;

  /// 카테고리별로 [count]개씩 심는다. 최신 글일수록 createdAt이 크다.
  Future<void> seed({
    required String category,
    required int count,
    String type = 'found',
    String location = '(1) 공학관',
    String authorUid = 'author1',
    bool resolved = false,
    int startIndex = 0,
  }) async {
    for (var i = 0; i < count; i++) {
      final index = startIndex + i;
      await items.add({
        'title': '$category $index',
        'description': '',
        'location': location,
        'locationDetail': '',
        'type': type,
        'category': category,
        'authorUid': authorUid,
        'authorNickname': '테스터',
        'resolved': resolved,
        'imageUrls': <String>[],
        'reportCount': 0,
        'viewCount': index,
        'createdAt': Timestamp.fromDate(
          DateTime(2026, 1, 1).add(Duration(minutes: index)),
        ),
      });
    }
  }

  setUp(() {
    firestore = FakeFirebaseFirestore();
    items = firestore.collection('items');
  });

  group('buildFeedQuery', () {
    test('카테고리 필터를 켜도 첫 페이지가 20개로 꽉 찬다', () async {
      // 최신 글 40개는 전부 '가방'이라, 클라이언트 필터 방식이었다면
      // 상위 20개에 '전자기기'가 하나도 안 잡혀 0건이 나왔을 상황이다.
      await seed(category: '전자기기', count: 30, startIndex: 0);
      await seed(category: '가방', count: 40, startIndex: 100);

      final snap = await buildFeedQuery(
        collection: items,
        typeFilter: 0,
        category: '전자기기',
        location: kAllFilterLabel,
        sortByPopular: false,
        limit: kInitialPageLimit,
      ).get();

      expect(snap.docs.length, kInitialPageLimit);
      expect(
        snap.docs.every((d) => d.data()['category'] == '전자기기'),
        isTrue,
        reason: '카테고리 필터가 서버 쿼리에 실려야 한다',
      );
    });

    test('"더 보기"로 limit을 늘리면 10개씩 더 나온다', () async {
      await seed(category: '전자기기', count: 45);

      final first = await buildFeedQuery(
        collection: items,
        typeFilter: 0,
        category: '전자기기',
        location: kAllFilterLabel,
        sortByPopular: false,
        limit: kInitialPageLimit,
      ).get();
      final second = await buildFeedQuery(
        collection: items,
        typeFilter: 0,
        category: '전자기기',
        location: kAllFilterLabel,
        sortByPopular: false,
        limit: kInitialPageLimit + kLoadMoreStep,
      ).get();

      expect(first.docs.length, 20);
      expect(second.docs.length, 30);
    });

    test('종류·카테고리·장소를 함께 걸면 모두 반영된다', () async {
      await seed(category: '가방', count: 5, type: 'lost', location: '(3) 의학관');
      await seed(
        category: '가방',
        count: 5,
        type: 'lost',
        location: '(1) 공학관',
        startIndex: 50,
      );
      await seed(
        category: '의류',
        count: 5,
        type: 'lost',
        location: '(3) 의학관',
        startIndex: 100,
      );
      await seed(
        category: '가방',
        count: 5,
        type: 'found',
        location: '(3) 의학관',
        startIndex: 150,
      );

      final snap = await buildFeedQuery(
        collection: items,
        typeFilter: 2, // 분실물
        category: '가방',
        location: '(3) 의학관',
        sortByPopular: false,
        limit: kInitialPageLimit,
      ).get();

      expect(snap.docs.length, 5);
      for (final doc in snap.docs) {
        expect(doc.data()['type'], 'lost');
        expect(doc.data()['category'], '가방');
        expect(doc.data()['location'], '(3) 의학관');
      }
    });

    test('필터를 모두 해제하면 전체가 최신순으로 나온다', () async {
      await seed(category: '전자기기', count: 3, startIndex: 0);
      await seed(category: '가방', count: 3, startIndex: 10);

      final snap = await buildFeedQuery(
        collection: items,
        typeFilter: 0,
        category: kAllFilterLabel,
        location: kAllFilterLabel,
        sortByPopular: false,
        limit: kInitialPageLimit,
      ).get();

      expect(snap.docs.length, 6);
      // createdAt 내림차순이므로 가장 늦게 심은 글이 맨 앞이다.
      expect(snap.docs.first.data()['title'], '가방 12');
    });

    test('조회순 정렬이면 viewCount 내림차순으로 나온다', () async {
      await seed(category: '전자기기', count: 5);

      final snap = await buildFeedQuery(
        collection: items,
        typeFilter: 0,
        category: kAllFilterLabel,
        location: kAllFilterLabel,
        sortByPopular: true,
        limit: kInitialPageLimit,
      ).get();

      final views = snap.docs
          .map((d) => (d.data()['viewCount'] as num).toInt())
          .toList();
      expect(views, [4, 3, 2, 1, 0]);
    });
  });

  group('buildMyPostsQuery', () {
    test('상태 필터를 켜도 첫 페이지가 20개로 꽉 찬다', () async {
      // 최신 글 30개는 전부 거래완료라, 클라이언트 필터 방식이었다면
      // '진행중'을 골랐을 때 상위 20개에서 0건이 나왔을 상황이다.
      await seed(category: '기타', count: 25, resolved: false, startIndex: 0);
      await seed(category: '기타', count: 30, resolved: true, startIndex: 100);

      final snap = await buildMyPostsQuery(
        collection: items,
        uid: 'author1',
        statusFilter: 1, // 진행중
        oldestFirst: false,
        limit: kInitialPageLimit,
      ).get();

      expect(snap.docs.length, kInitialPageLimit);
      expect(snap.docs.every((d) => d.data()['resolved'] == false), isTrue);
    });

    test('거래완료 필터는 완료된 글만, 다른 작성자 글은 제외한다', () async {
      await seed(category: '기타', count: 4, resolved: true);
      await seed(category: '기타', count: 3, resolved: false, startIndex: 50);
      await seed(
        category: '기타',
        count: 5,
        resolved: true,
        authorUid: 'other',
        startIndex: 100,
      );

      final snap = await buildMyPostsQuery(
        collection: items,
        uid: 'author1',
        statusFilter: 2, // 거래완료
        oldestFirst: false,
        limit: kInitialPageLimit,
      ).get();

      expect(snap.docs.length, 4);
      for (final doc in snap.docs) {
        expect(doc.data()['authorUid'], 'author1');
        expect(doc.data()['resolved'], true);
      }
    });

    test('오래된순 정렬이면 가장 먼저 쓴 글이 맨 앞에 온다', () async {
      await seed(category: '기타', count: 3);

      final snap = await buildMyPostsQuery(
        collection: items,
        uid: 'author1',
        statusFilter: 0,
        oldestFirst: true,
        limit: kInitialPageLimit,
      ).get();

      expect(snap.docs.first.data()['title'], '기타 0');
      expect(snap.docs.last.data()['title'], '기타 2');
    });
  });

  group('buildCategoryCountQuery', () {
    test('장소 필터가 걸리면 그 장소의 글만 센다', () async {
      await seed(category: '가방', count: 3, location: '(1) 공학관');
      await seed(category: '가방', count: 7, location: '(3) 의학관', startIndex: 50);

      final snap = await buildCategoryCountQuery(
        collection: items,
        typeFilter: 0,
        location: '(3) 의학관',
      ).where('category', isEqualTo: '가방').get();

      expect(snap.docs.length, 7);
    });
  });
}
