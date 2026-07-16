import 'package:shared_preferences/shared_preferences.dart';

const String _kRecentSearchesKey = 'recent_searches_v1';
const int _kMaxRecentSearches = 8;

/// 이 기기에서 홈 피드에 검색했던 검색어 목록(최신순, 최대 8개)을 불러온다.
Future<List<String>> loadRecentSearches() async {
  final prefs = await SharedPreferences.getInstance();
  return prefs.getStringList(_kRecentSearchesKey) ?? const [];
}

/// 검색어를 최근 검색 목록 맨 앞에 추가한다. 이미 있던 검색어는 중복 없이
/// 맨 앞으로 옮기고, 목록이 8개를 넘으면 오래된 것부터 잘라낸다.
Future<void> addRecentSearch(String query) async {
  final trimmed = query.trim();
  if (trimmed.isEmpty) return;

  final prefs = await SharedPreferences.getInstance();
  final current = prefs.getStringList(_kRecentSearchesKey) ?? const [];
  final updated = [trimmed, ...current.where((q) => q != trimmed)];
  await prefs.setStringList(
    _kRecentSearchesKey,
    updated.take(_kMaxRecentSearches).toList(),
  );
}

Future<void> removeRecentSearch(String query) async {
  final prefs = await SharedPreferences.getInstance();
  final current = prefs.getStringList(_kRecentSearchesKey) ?? const [];
  await prefs.setStringList(
    _kRecentSearchesKey,
    current.where((q) => q != query).toList(),
  );
}

Future<void> clearRecentSearches() async {
  final prefs = await SharedPreferences.getInstance();
  await prefs.remove(_kRecentSearchesKey);
}
