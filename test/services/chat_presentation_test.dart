import 'package:flutter_test/flutter_test.dart';
import 'package:latte/services/chat_presentation.dart';

void main() {
  group('채팅 날짜와 상태', () {
    test('오늘 시각은 오전·오후와 12시를 구분한다', () {
      final now = DateTime(2026, 10, 24, 18);
      expect(
        formatChatListTime(DateTime(2026, 10, 24, 0, 5), now: now),
        '오전 12:05',
      );
      expect(
        formatChatListTime(DateTime(2026, 10, 24, 12, 9), now: now),
        '오후 12:09',
      );
      expect(
        formatChatListTime(DateTime(2026, 10, 24, 15, 20), now: now),
        '오후 3:20',
      );
    });

    test('자정과 연도 경계에서도 어제·과거 날짜를 구분한다', () {
      final now = DateTime(2027, 1, 1, 0, 1);
      expect(formatChatDay(DateTime(2027, 1, 1), now: now), '오늘');
      expect(formatChatDay(DateTime(2026, 12, 31, 23, 59), now: now), '어제');
      expect(formatChatDay(DateTime(2026, 12, 30), now: now), '2026년 12월 30일');
      expect(
        isSameChatDay(DateTime(2026, 10, 23, 23, 59), DateTime(2026, 10, 24)),
        isFalse,
      );
    });

    test('삭제 상태를 먼저 표시하고 실제 완료 정보도 반영한다', () {
      expect(chatItemStatus(), '진행 중');
      expect(chatItemStatus(resolutionStatus: 'pending'), '확인 대기');
      expect(chatItemStatus(resolutionStatus: 'confirmed'), '확인 완료');
      expect(chatItemStatus(resolutionStatus: 'done'), '전달 완료');
      expect(chatItemStatus(itemResolved: true), '전달 완료');
      expect(
        chatItemStatus(itemDeleted: true, resolutionStatus: 'done'),
        '게시글 삭제됨',
      );
    });
  });

  group('새 메시지 안내', () {
    final start = DateTime(2026, 10, 24, 10);
    ChatTimelineMessage message(String id, int minute, {bool mine = false}) =>
        ChatTimelineMessage(
          id: id,
          isMine: mine,
          sentAt: start.add(Duration(minutes: minute)),
        );

    test('첫 목록은 새 메시지로 세지 않고 아래에서 도착한 메시지는 바로 따라간다', () {
      final tracker = ChatTimelineTracker();
      expect(tracker.observe([message('a', 0)], nearBottom: true), isTrue);
      expect(tracker.pendingCount, 0);
      expect(
        tracker.observe([message('b', 1), message('a', 0)], nearBottom: true),
        isTrue,
      );
      expect(tracker.pendingCount, 0);
    });

    test('과거 대화를 읽는 동안 새 메시지를 모으고 같은 스냅샷을 중복 계산하지 않는다', () {
      final tracker = ChatTimelineTracker();
      tracker.observe([message('a', 0)], nearBottom: true);
      expect(
        tracker.observe([message('b', 1), message('a', 0)], nearBottom: false),
        isFalse,
      );
      tracker.observe([
        message('c', 1),
        message('b', 1),
        message('a', 0),
      ], nearBottom: false);
      tracker.observe([
        message('c', 1),
        message('b', 1),
        message('a', 0),
      ], nearBottom: false);
      expect(tracker.pendingCount, 2);
      tracker.acknowledge();
      expect(tracker.pendingCount, 0);
    });

    test('캐시 뒤에 도착한 과거 기록은 안내를 만들거나 스크롤을 이동시키지 않는다', () {
      final tracker = ChatTimelineTracker();
      tracker.observe([message('a', 5)], nearBottom: true);
      expect(
        tracker.observe([
          message('a', 5),
          message('older', 0),
        ], nearBottom: false),
        isFalse,
      );
      expect(tracker.pendingCount, 0);
    });

    test('본인 전송은 이전 대화를 읽고 있어도 최신 메시지로 이동한다', () {
      final tracker = ChatTimelineTracker();
      tracker.observe([message('a', 0)], nearBottom: true);
      expect(
        tracker.observe([
          message('mine', 1, mine: true),
          message('a', 0),
        ], nearBottom: false),
        isTrue,
      );
      expect(tracker.pendingCount, 0);
    });

    test('서버 시각이 확정되거나 맨 아래로 돌아와도 새 메시지가 중복되지 않는다', () {
      final tracker = ChatTimelineTracker();
      tracker.observe([message('a', 0)], nearBottom: true);
      tracker.observe([
        const ChatTimelineMessage(id: 'b', isMine: false),
      ], nearBottom: false);
      tracker.observe([message('b', 1)], nearBottom: false);
      expect(tracker.pendingCount, 1);
      tracker.observe([message('b', 1)], nearBottom: true);
      expect(tracker.pendingCount, 0);
    });
  });
}
