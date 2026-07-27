import 'package:cloud_firestore/cloud_firestore.dart';

/// 채팅 메시지 전송의 데이터 계층.
///
/// UI(입력창 비우기·전송 중 표시)와 별개로, 같은 인스턴스에서 텍스트 전송이
/// 아직 진행 중이면 두 번째 호출을 건너뛴다. 전송 버튼 연타나 엔터 반복으로
/// 같은 메시지가 두 번 저장되고 상대방 안읽음 수가 두 번 증가하는 것을
/// 막는 서비스 계층 방어다(입력창 선(先) 비움과 함께 이중 안전장치).
///
/// in-flight 예약은 첫 `await` 이전(동기 구간)에 끝나므로, 같은 프레임에
/// 두 번 호출돼도 두 번째 호출이 끼어들 수 없다.
class ChatMessageSender {
  ChatMessageSender(this.firestore);

  final FirebaseFirestore firestore;

  bool _sendingText = false;

  /// 텍스트 메시지를 보낸다. 이미 전송 중이거나 내용이 비어 있으면 아무 것도
  /// 하지 않고 false를 반환한다. 실제로 전송했으면 true.
  Future<bool> sendText({
    required String chatId,
    required String senderUid,
    required String otherUid,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (_sendingText || trimmed.isEmpty) return false;
    _sendingText = true;
    try {
      final chatRef = firestore.collection('chats').doc(chatId);
      final messageRef = chatRef.collection('messages').doc();
      final batch = firestore.batch();
      batch.set(messageRef, {
        'senderUid': senderUid,
        'type': 'text',
        'text': trimmed,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(chatRef, {
        'lastMessage': trimmed,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastReadAt.$senderUid': FieldValue.serverTimestamp(),
        'unreadCount.$otherUid': FieldValue.increment(1),
        'typing.$senderUid': false,
      });
      await batch.commit();
      return true;
    } finally {
      _sendingText = false;
    }
  }
}
