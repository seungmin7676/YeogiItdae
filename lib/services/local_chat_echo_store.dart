import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

const int kMaxLocalChatEchoes = 200;

/// 서버가 차단 관계로 거부한 메시지를 발신자 기기에만 표시하기 위한 기록.
class LocalChatEcho {
  final String id;
  final String text;
  final DateTime sentAt;

  const LocalChatEcho({
    required this.id,
    required this.text,
    required this.sentAt,
  });

  Map<String, dynamic> toJson() => {
    'id': id,
    'text': text,
    'sentAt': sentAt.toUtc().toIso8601String(),
  };

  static LocalChatEcho? fromJson(Object? value) {
    if (value is! Map) return null;
    final id = value['id'];
    final text = value['text'];
    final sentAt = DateTime.tryParse(value['sentAt'] as String? ?? '');
    if (id is! String || text is! String || sentAt == null) return null;
    return LocalChatEcho(id: id, text: text, sentAt: sentAt.toLocal());
  }
}

/// 계정과 채팅방별로 로컬 전용 말풍선을 분리해 보관한다.
class LocalChatEchoStore {
  static const _keyPrefix = 'local_chat_echoes_v1';

  String _key(String userUid, String chatId) => '$_keyPrefix:$userUid:$chatId';

  Future<List<LocalChatEcho>> load({
    required String userUid,
    required String chatId,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    return _decode(preferences.getString(_key(userUid, chatId)));
  }

  Future<void> append({
    required String userUid,
    required String chatId,
    required LocalChatEcho echo,
  }) async {
    final preferences = await SharedPreferences.getInstance();
    final key = _key(userUid, chatId);
    final echoes = _decode(preferences.getString(key));
    echoes.removeWhere((entry) => entry.id == echo.id);
    echoes.add(echo);
    echoes.sort((a, b) => a.sentAt.compareTo(b.sentAt));
    if (echoes.length > kMaxLocalChatEchoes) {
      echoes.removeRange(0, echoes.length - kMaxLocalChatEchoes);
    }
    await preferences.setString(
      key,
      jsonEncode(echoes.map((entry) => entry.toJson()).toList()),
    );
  }

  List<LocalChatEcho> _decode(String? raw) {
    if (raw == null || raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! List) return [];
      return decoded
          .map(LocalChatEcho.fromJson)
          .whereType<LocalChatEcho>()
          .toList();
    } catch (_) {
      return [];
    }
  }
}
