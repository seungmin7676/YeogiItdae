import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:latte/services/chat_actions.dart';

void main() {
  late FakeFirebaseFirestore firestore;
  late ChatMessageSender sender;

  const chatId = 'item1_uidA_uidB';
  const me = 'uidA';
  const other = 'uidB';

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    sender = ChatMessageSender(firestore);
    await firestore.collection('chats').doc(chatId).set({
      'participants': [me, other],
      'lastMessage': '',
      'unreadCount': {me: 0, other: 0},
      'typing': {me: false, other: false},
    });
  });

  Future<int> messageCount() async {
    final snap = await firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .get();
    return snap.docs.length;
  }

  Future<int> otherUnread() async {
    final doc = await firestore.collection('chats').doc(chatId).get();
    return (doc.data()!['unreadCount'] as Map)[other] as int;
  }

  test('메시지를 보내면 문서 1건이 저장되고 상대 안읽음 수가 1 증가한다', () async {
    final sent = await sender.sendText(
      chatId: chatId,
      senderUid: me,
      otherUid: other,
      text: '안녕하세요',
    );

    expect(sent, isTrue);
    expect(await messageCount(), 1);
    expect(await otherUnread(), 1);
    final chat = await firestore.collection('chats').doc(chatId).get();
    expect(chat.data()!['lastMessage'], '안녕하세요');
    // 전송하면 내 "입력 중" 표시는 꺼진다.
    expect((chat.data()!['typing'] as Map)[me], isFalse);
  });

  test('보내는 텍스트의 앞뒤 공백은 제거되고, 공백뿐이면 전송하지 않는다', () async {
    expect(
      await sender.sendText(
        chatId: chatId,
        senderUid: me,
        otherUid: other,
        text: '   ',
      ),
      isFalse,
    );
    expect(await messageCount(), 0);

    await sender.sendText(
      chatId: chatId,
      senderUid: me,
      otherUid: other,
      text: '  여백  ',
    );
    final snap = await firestore
        .collection('chats')
        .doc(chatId)
        .collection('messages')
        .get();
    expect(snap.docs.single.data()['text'], '여백');
  });

  test('같은 프레임에 두 번 호출해도(연타·엔터 반복) 메시지는 한 번만 저장된다', () async {
    // 첫 호출은 await 이전 동기 구간에서 전송 중 플래그를 세우므로,
    // 곧바로 이어진 두 번째 호출은 건너뛴다(false).
    final results = await Future.wait([
      sender.sendText(
        chatId: chatId,
        senderUid: me,
        otherUid: other,
        text: '중복 방지',
      ),
      sender.sendText(
        chatId: chatId,
        senderUid: me,
        otherUid: other,
        text: '중복 방지',
      ),
    ]);

    expect(results.where((r) => r).length, 1);
    expect(results.where((r) => !r).length, 1);
    expect(await messageCount(), 1);
    // 상대방 안읽음 수도 딱 1만 증가해야 한다.
    expect(await otherUnread(), 1);
  });

  test('전송이 끝난 뒤에는 다음 메시지를 다시 보낼 수 있다(in-flight 해제)', () async {
    await sender.sendText(
      chatId: chatId,
      senderUid: me,
      otherUid: other,
      text: '첫 번째',
    );
    final second = await sender.sendText(
      chatId: chatId,
      senderUid: me,
      otherUid: other,
      text: '두 번째',
    );

    expect(second, isTrue);
    expect(await messageCount(), 2);
    expect(await otherUnread(), 2);
  });
}
