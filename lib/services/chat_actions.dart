import 'dart:convert';

import 'package:cloud_firestore/cloud_firestore.dart';

import 'backend_exception.dart';
import 'backend_http.dart';

const int kMaxChatMessageLength = 2000;
const int kChatMessagePageSize = 50;

Query<Map<String, dynamic>> buildChatMessagesQuery(
  CollectionReference<Map<String, dynamic>> messages, {
  Timestamp? clearedAt,
  DocumentSnapshot<Map<String, dynamic>>? before,
}) {
  Query<Map<String, dynamic>> query = messages.orderBy(
    'createdAt',
    descending: true,
  );
  if (clearedAt != null) {
    query = query.where('createdAt', isGreaterThan: clearedAt);
  }
  if (before != null) query = query.startAfterDocument(before);
  return query.limit(kChatMessagePageSize);
}

/// 새 채팅방의 로컬 대기 쓰기를 서버 확정된 문서로 오인해 메시지 쿼리를
/// 너무 일찍 열지 않도록 한다. 부모 채팅 문서가 서버에 아직 없을 때 하위
/// 컬렉션 쿼리를 시작하면 보안 규칙이 거부하고, 그 스트림은 재입장할 때까지
/// 오류 상태에 머문다.
bool shouldStartMessagesStream({
  required bool chatExists,
  required bool hasPendingWrites,
}) => chatExists && !hasPendingWrites;

/// 차단 관계의 메시지는 Firestore 규칙에서 permission-denied로 거부된다.
/// 차단 여부를 발신자에게 노출하지 않기 위해 이 경우에만 서버 오류 대신
/// 발신자 기기의 로컬 말풍선으로 남긴다. 네트워크·인증 등 다른 실패까지
/// 숨기면 실제 장애를 알아차릴 수 없으므로 구분한다.
bool shouldKeepAsLocalChatEcho(Object error, {bool blockConfirmed = false}) =>
    blockConfirmed &&
    error is FirebaseException &&
    error.code == 'permission-denied';

/// 다른 사용자 차단 문서를 공개하지 않고 실제 차단으로 거부됐는지 확인한다.
/// 서버 확인 실패는 정상 전송으로 위장하지 않고 원래 오류로 처리한다.
Future<bool> confirmBlockedChatSend({
  required String chatId,
  required String recipientUid,
  String? itemId,
}) async {
  final response = await postBackend(
    Uri.parse('$kVerifyBackendUrl/api/send-push'),
    headers: await backendSecurityHeaders(
      authenticate: true,
    ).timeout(const Duration(seconds: 10)),
    body: jsonEncode({
      'action': 'check-chat-rejection',
      'chatId': chatId,
      'recipientUid': recipientUid,
      'itemId': ?itemId,
    }),
  );
  if (response.statusCode != 200) return false;
  final decoded = jsonDecode(response.body);
  return decoded is Map && decoded['localOnly'] == true;
}

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
  /// 하지 않고 null을 반환한다. 실제로 전송했으면 서버 검증에 쓸 메시지 ID.
  Future<String?> sendText({
    required String chatId,
    required String senderUid,
    required String otherUid,
    required String text,
  }) async {
    final trimmed = text.trim();
    if (_sendingText ||
        trimmed.isEmpty ||
        trimmed.length > kMaxChatMessageLength) {
      return null;
    }
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
      return messageRef.id;
    } finally {
      _sendingText = false;
    }
  }
}
