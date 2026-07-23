import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latte/models/lost_found_item.dart';

void main() {
  group('ItemType.fromValue', () {
    test('알려진 값은 그대로 매핑한다', () {
      expect(ItemType.fromValue('found'), ItemType.found);
      expect(ItemType.fromValue('lost'), ItemType.lost);
    });

    test('알 수 없는 값은 found로 대체한다', () {
      expect(ItemType.fromValue('알수없음'), ItemType.found);
    });
  });

  group('relativeTime', () {
    test('null이면 빈 문자열을 반환한다', () {
      expect(relativeTime(null), '');
    });

    test('1분 미만이면 방금 전', () {
      expect(relativeTime(DateTime.now()), '방금 전');
    });

    test('분 단위로 표시한다', () {
      final time = DateTime.now().subtract(const Duration(minutes: 5));
      expect(relativeTime(time), '5분 전');
    });

    test('시간 단위로 표시한다', () {
      final time = DateTime.now().subtract(const Duration(hours: 3));
      expect(relativeTime(time), '3시간 전');
    });

    test('정확히 하루 전이면 어제로 표시한다', () {
      final time = DateTime.now().subtract(const Duration(days: 1));
      expect(relativeTime(time), '어제');
    });

    test('일주일 이내면 N일 전으로 표시한다', () {
      final time = DateTime.now().subtract(const Duration(days: 3));
      expect(relativeTime(time), '3일 전');
    });

    test('일주일이 넘으면 날짜(YYYY.MM.DD)로 표시한다', () {
      final time = DateTime.now().subtract(const Duration(days: 10));
      final expected =
          '${time.year}.${time.month.toString().padLeft(2, '0')}.${time.day.toString().padLeft(2, '0')}';
      expect(relativeTime(time), expected);
    });
  });

  group('LostFoundItem.isHidden', () {
    LostFoundItem itemWithReportCount(int reportCount) => LostFoundItem(
      title: '제목',
      location: '장소',
      type: ItemType.found,
      authorUid: 'uid',
      authorNickname: '닉네임',
      reportCount: reportCount,
    );

    test('신고 수가 임계값보다 낮으면 숨겨지지 않는다', () {
      expect(itemWithReportCount(kReportThreshold - 1).isHidden, isFalse);
    });

    test('신고 수가 임계값에 도달하면 숨겨진다', () {
      expect(itemWithReportCount(kReportThreshold).isHidden, isTrue);
    });
  });

  group('LostFoundItem.fromDoc', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('imageUrls 필드가 있으면 그대로 사용한다', () async {
      final ref = await firestore.collection('items').add({
        'title': '지갑',
        'description': '검은색 반지갑',
        'location': '(1) 공학관',
        'locationDetail': '1층 로비',
        'type': 'found',
        'category': '지갑/카드/현금',
        'authorUid': 'uid1',
        'authorNickname': '홍길동',
        'resolved': false,
        'imageUrls': ['https://example.com/1.png', 'https://example.com/2.png'],
        'reportCount': 1,
        'viewCount': 5,
        'createdAt': Timestamp.now(),
      });
      final item = LostFoundItem.fromDoc(await ref.get());

      expect(item.id, ref.id);
      expect(item.title, '지갑');
      expect(item.type, ItemType.found);
      expect(item.imageUrls, [
        'https://example.com/1.png',
        'https://example.com/2.png',
      ]);
      expect(item.reportCount, 1);
      expect(item.viewCount, 5);
      expect(item.createdAt, isNotNull);
    });

    test('imageUrls가 없고 옛 imageUrl 필드만 있으면 한 장짜리 목록으로 변환한다', () async {
      final ref = await firestore.collection('items').add({
        'title': '우산',
        'location': '(2) 대학본부-인문1관',
        'type': 'lost',
        'authorUid': 'uid2',
        'authorNickname': '김철수',
        'resolved': false,
        'imageUrl': 'https://example.com/old.png',
      });
      final item = LostFoundItem.fromDoc(await ref.get());

      expect(item.imageUrls, ['https://example.com/old.png']);
      expect(item.description, '');
      expect(item.category, '기타');
    });

    test('필드가 아예 없는 문서도 기본값으로 안전하게 매핑한다', () async {
      final ref = await firestore.collection('items').add({});
      final item = LostFoundItem.fromDoc(await ref.get());

      expect(item.title, '');
      expect(item.authorNickname, '익명');
      expect(item.type, ItemType.found);
      expect(item.imageUrls, isEmpty);
      expect(item.resolved, isFalse);
      expect(item.reportCount, 0);
      expect(item.viewCount, 0);
    });
  });

  group('LostFoundItem.fromDocs', () {
    late FakeFirebaseFirestore firestore;

    setUp(() {
      firestore = FakeFirebaseFirestore();
    });

    test('손상된 문서 한 건이 있어도 나머지 정상 문서는 목록에 포함된다', () async {
      final good1 = await firestore.collection('items').add({
        'title': '정상 글 1',
        'authorUid': 'uid1',
        'authorNickname': '홍길동',
      });
      // title에 문자열이 아닌 값이 들어간 손상 문서 — 과거에는 이 한 건의
      // 캐스팅 예외가 목록 전체 build를 실패시켜 화면이 통째로 깨졌다.
      await firestore.collection('items').add({
        'title': 12345,
        'authorUid': 'uid2',
      });
      final good2 = await firestore.collection('items').add({
        'title': '정상 글 2',
        'authorUid': 'uid3',
        'authorNickname': '김철수',
      });

      final snap = await firestore.collection('items').get();
      final items = LostFoundItem.fromDocs(snap.docs);

      expect(items.length, 2);
      expect(items.map((i) => i.id).toSet(), {good1.id, good2.id});
    });

    test('모든 문서가 정상이면 전부 변환된다', () async {
      await firestore.collection('items').add({'title': 'A'});
      await firestore.collection('items').add({'title': 'B'});

      final snap = await firestore.collection('items').get();
      expect(LostFoundItem.fromDocs(snap.docs).length, 2);
    });
  });

  group('LostFoundItem.toMap / toUpdateMap', () {
    test('toMap은 새 글 기본값(신고·조회수 0)을 포함한다', () {
      final item = LostFoundItem(
        title: '노트북 파우치',
        location: '(3) 의학관',
        type: ItemType.found,
        category: '가방',
        authorUid: 'uid3',
        authorNickname: '이영희',
        imageUrls: const ['https://example.com/a.png'],
      );
      final map = item.toMap();

      expect(map['title'], '노트북 파우치');
      expect(map['type'], 'found');
      expect(map['reportCount'], 0);
      expect(map['viewCount'], 0);
      expect(map['imageUrls'], ['https://example.com/a.png']);
      expect(map.containsKey('createdAt'), isTrue);
    });

    test('toUpdateMap은 작성자·신고·조회수 등 불변 필드를 포함하지 않는다', () {
      final item = LostFoundItem(
        title: '수정된 제목',
        location: '(4) 인문2관',
        type: ItemType.lost,
        authorUid: 'uid4',
        authorNickname: '박민수',
        resolved: true,
      );
      final map = item.toUpdateMap();

      expect(map['title'], '수정된 제목');
      expect(map['resolved'], isTrue);
      expect(map.containsKey('authorUid'), isFalse);
      expect(map.containsKey('authorNickname'), isFalse);
      expect(map.containsKey('reportCount'), isFalse);
      expect(map.containsKey('viewCount'), isFalse);
      expect(map.containsKey('createdAt'), isFalse);
    });
  });
}
