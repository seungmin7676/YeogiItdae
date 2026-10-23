bool isSameChatDay(DateTime first, DateTime second) =>
    first.year == second.year &&
    first.month == second.month &&
    first.day == second.day;

String formatChatTime(DateTime time) {
  final hour = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '${time.hour < 12 ? '오전' : '오후'} $hour:$minute';
}

String formatChatDay(DateTime time, {DateTime? now}) {
  final today = now ?? DateTime.now();
  if (isSameChatDay(time, today)) return '오늘';
  final yesterday = DateTime(today.year, today.month, today.day - 1);
  if (isSameChatDay(time, yesterday)) return '어제';
  return '${time.year == today.year ? '' : '${time.year}년 '}'
      '${time.month}월 ${time.day}일';
}

String formatChatListTime(DateTime time, {DateTime? now}) =>
    isSameChatDay(time, now ?? DateTime.now())
    ? formatChatTime(time)
    : formatChatDay(time, now: now);

String chatItemStatus({
  String? resolutionStatus,
  bool itemDeleted = false,
  bool itemResolved = false,
}) {
  if (itemDeleted) return '게시글 삭제됨';
  if (itemResolved || resolutionStatus == 'done') return '전달 완료';
  if (resolutionStatus == 'pending') return '확인 대기';
  if (resolutionStatus == 'confirmed') return '확인 완료';
  return '진행 중';
}

class ChatTimelineMessage {
  const ChatTimelineMessage({
    required this.id,
    required this.isMine,
    this.sentAt,
  });

  final String id;
  final bool isMine;
  final DateTime? sentAt;
}

/// 라이브 쿼리에 새로 들어온 메시지만 센다. 캐시 뒤에 도착한 과거 기록,
/// 같은 메시지의 서버 시각 확정·읽음 갱신은 새 메시지로 세지 않는다.
class ChatTimelineTracker {
  final Set<String> _seen = {};
  final Set<String> _pending = {};
  DateTime? _latestTime;
  bool _initialized = false;

  int get pendingCount => _pending.length;
  void acknowledge() => _pending.clear();

  bool observe(
    Iterable<ChatTimelineMessage> messages, {
    required bool nearBottom,
  }) {
    final previousLatest = _latestTime;
    var shouldScroll = false;
    var hasMessages = false;
    for (final message in messages) {
      hasMessages = true;
      final unseen = _seen.add(message.id);
      final time = message.sentAt;
      if (time != null && (_latestTime == null || time.isAfter(_latestTime!))) {
        _latestTime = time;
      }
      if (!_initialized || !unseen) continue;
      if (time != null &&
          previousLatest != null &&
          time.isBefore(previousLatest)) {
        continue;
      }
      if (message.isMine || nearBottom) {
        shouldScroll = true;
      } else {
        _pending.add(message.id);
      }
    }
    if (!_initialized && hasMessages) shouldScroll = true;
    _initialized = true;
    if (nearBottom) acknowledge();
    return shouldScroll;
  }
}
