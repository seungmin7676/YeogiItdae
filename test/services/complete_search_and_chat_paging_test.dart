import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latte/services/chat_actions.dart';
import 'package:latte/services/feed_search.dart';

void main() {
  test('한 글자와 설명 500자 이후 단어도 첫 100개 밖의 옛 글에서 찾는다', () async {
    final db = FakeFirebaseFirestore();
    for (var index = 0; index < 145; index++) {
      await db.collection('items').doc('item-$index').set({
        'title': index == 140 ? '폰을 찾습니다' : '등록 물건',
        'description': index == 144 ? '${'가' * 900}특별한표식' : '',
        'hidden': false,
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(200000 - index),
      });
    }
    final query = db
        .collection('items')
        .where('hidden', isEqualTo: false)
        .orderBy('createdAt', descending: true);
    final single = await FeedSearchPager(query: query, search: '폰').loadNext();
    expect(single.map((item) => item.id), ['item-140']);
    final tail = await FeedSearchPager(
      query: query,
      search: '특별한표식',
    ).loadNext();
    expect(tail.map((item) => item.id), ['item-144']);
  });

  test('검색 결과의 다음 페이지는 중복이나 누락 없이 이어진다', () async {
    final db = FakeFirebaseFirestore();
    for (var index = 0; index < 45; index++) {
      await db.collection('items').doc('$index').set({
        'title': '지갑 $index',
        'createdAt': Timestamp.fromMillisecondsSinceEpoch(index),
      });
    }
    final pager = FeedSearchPager(
      query: db.collection('items').orderBy('createdAt'),
      search: '지갑',
    );
    expect(await pager.loadNext(), hasLength(20));
    expect(await pager.loadNext(), hasLength(40));
    final all = await pager.loadNext();
    expect(all.map((item) => item.id).toSet(), hasLength(45));
    expect(pager.hasMore, isFalse);
  });

  test('같은 시각의 채팅 125건도 50건씩 빠짐없이 읽고 나가기 이전은 제외한다', () async {
    final db = FakeFirebaseFirestore();
    final messages = db.collection('chats').doc('chat').collection('messages');
    final timestamp = Timestamp.fromMillisecondsSinceEpoch(2000);
    for (var index = 0; index < 125; index++) {
      await messages.doc('message-${index.toString().padLeft(3, '0')}').set({
        'createdAt': timestamp,
      });
    }
    await messages.doc('old').set({
      'createdAt': Timestamp.fromMillisecondsSinceEpoch(1000),
    });
    final first = await buildChatMessagesQuery(
      messages,
      clearedAt: Timestamp.fromMillisecondsSinceEpoch(1500),
    ).get();
    expect(first.docs, hasLength(50));
    final second = await buildChatMessagesQuery(
      messages,
      clearedAt: Timestamp.fromMillisecondsSinceEpoch(1500),
      before: first.docs.last,
    ).get();
    final third = await buildChatMessagesQuery(
      messages,
      clearedAt: Timestamp.fromMillisecondsSinceEpoch(1500),
      before: second.docs.last,
    ).get();
    expect(second.docs, hasLength(50));
    expect(third.docs, hasLength(25));
    expect(
      [
        ...first.docs,
        ...second.docs,
        ...third.docs,
      ].map((doc) => doc.id).toSet(),
      hasLength(125),
    );
  });
}
