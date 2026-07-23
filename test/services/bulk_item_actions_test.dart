import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latte/services/bulk_item_actions.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late BulkItemActions actions;

  setUp(() {
    firestore = FakeFirebaseFirestore();
    actions = BulkItemActions(firestore.collection('items'));
  });

  Future<String> seedItem({bool resolved = false}) async {
    final ref = await firestore.collection('items').add({
      'title': '테스트 글',
      'authorUid': 'uid1',
      'resolved': resolved,
    });
    return ref.id;
  }

  group('markResolved', () {
    test('선택한 여러 글이 각각 정확히 한 번씩 완료 처리된다', () async {
      final ids = [await seedItem(), await seedItem(), await seedItem()];

      final result = await actions.markResolved(ids);

      expect(result.succeeded.toSet(), ids.toSet());
      expect(result.failed, isEmpty);
      expect(result.notFound, isEmpty);
      expect(result.skipped, isEmpty);
      for (final id in ids) {
        final doc = await firestore.collection('items').doc(id).get();
        expect(doc.data()?['resolved'], isTrue);
      }
    });

    test('입력 목록에 같은 id가 중복되어도 한 번만 처리된다', () async {
      final id = await seedItem();

      final result = await actions.markResolved([id, id, id]);

      // 결과 목록 어디에도 같은 id가 두 번 나타나지 않는다.
      expect(result.succeeded, [id]);
      expect(result.skipped, isEmpty);
    });

    test('이미 완료된 글을 다시 완료 처리해도 안전하게 성공한다(멱등성)', () async {
      final id = await seedItem(resolved: true);

      final result = await actions.markResolved([id]);

      expect(result.succeeded, [id]);
      final doc = await firestore.collection('items').doc(id).get();
      expect(doc.data()?['resolved'], isTrue);
    });

    test('없는 글(이미 삭제됨)이 섞여 있어도 나머지는 정상 처리된다(부분 실패 격리)', () async {
      final good1 = await seedItem();
      final good2 = await seedItem();

      final result = await actions.markResolved([good1, 'deleted-item', good2]);

      expect(result.succeeded.toSet(), {good1, good2});
      expect(result.notFound, ['deleted-item']);
      expect(result.failed, isEmpty);
      for (final id in [good1, good2]) {
        final doc = await firestore.collection('items').doc(id).get();
        expect(doc.data()?['resolved'], isTrue);
      }
    });

    test('같은 작업이 처리 중에 다시 호출되면 처리 중인 글은 건너뛴다(in-flight 방어)', () async {
      final ids = [await seedItem(), await seedItem()];

      // 첫 요청이 끝나기 전에(await 없이) 같은 요청이 다시 들어온 상황.
      final first = actions.markResolved(ids);
      final second = actions.markResolved(ids);

      final firstResult = await first;
      final secondResult = await second;

      expect(firstResult.succeeded.toSet(), ids.toSet());
      expect(secondResult.succeeded, isEmpty);
      expect(secondResult.skipped.toSet(), ids.toSet());
    });

    test('작업이 끝난 뒤에는 같은 글을 다시 처리할 수 있다(in-flight 해제)', () async {
      final id = await seedItem();

      await actions.markResolved([id]);
      final again = await actions.markResolved([id]);

      expect(again.succeeded, [id]);
      expect(again.skipped, isEmpty);
    });

    test('부분 실패 후 실패분만 재시도하면 그 글만 처리된다', () async {
      final good = await seedItem();
      final first = await actions.markResolved([good, 'missing-1']);
      expect(first.succeeded, [good]);

      // 화면은 succeeded/notFound를 선택에서 제거하고 failed만 남기므로,
      // 재시도 요청에는 실패분만 들어온다. 이때 이미 성공한 글은 다시
      // 요청되지 않는다.
      final retryTargets = first.failed;
      final second = await actions.markResolved(retryTargets);
      expect(second.succeeded, isEmpty);
      expect(second.notFound, isEmpty);
    });
  });

  group('deleteItems', () {
    test('선택한 글을 삭제하고 성공 목록으로 보고한다', () async {
      final ids = [await seedItem(), await seedItem()];

      final result = await actions.deleteItems(ids);

      expect(result.succeeded.toSet(), ids.toSet());
      for (final id in ids) {
        final doc = await firestore.collection('items').doc(id).get();
        expect(doc.exists, isFalse);
      }
    });

    test('삭제 중복 호출 시 처리 중인 글은 건너뛴다', () async {
      final id = await seedItem();

      final first = actions.deleteItems([id]);
      final second = actions.deleteItems([id]);

      expect((await first).succeeded, [id]);
      expect((await second).skipped, [id]);
    });
  });
}
