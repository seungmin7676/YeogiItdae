import 'package:flutter_test/flutter_test.dart';
import 'package:latte/services/local_chat_echo_store.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
  });

  test('차단으로 거부된 메시지를 계정과 채팅방별로 다시 불러온다', () async {
    final store = LocalChatEchoStore();
    final echo = LocalChatEcho(
      id: 'local-1',
      text: '전송된 것처럼 보여요',
      sentAt: DateTime(2026, 9, 11, 16, 30),
    );

    await store.append(userUid: 'me', chatId: 'chat-a', echo: echo);

    final loaded = await store.load(userUid: 'me', chatId: 'chat-a');
    expect(loaded, hasLength(1));
    expect(loaded.single.id, echo.id);
    expect(loaded.single.text, echo.text);
    expect(loaded.single.sentAt, echo.sentAt);
    expect(await store.load(userUid: 'other', chatId: 'chat-a'), isEmpty);
    expect(await store.load(userUid: 'me', chatId: 'chat-b'), isEmpty);
  });

  test('손상된 로컬 데이터는 채팅 화면을 막지 않고 빈 목록으로 복구한다', () async {
    SharedPreferences.setMockInitialValues({
      'local_chat_echoes_v1:me:chat-a': '{broken',
    });

    expect(
      await LocalChatEchoStore().load(userUid: 'me', chatId: 'chat-a'),
      isEmpty,
    );
  });
}
