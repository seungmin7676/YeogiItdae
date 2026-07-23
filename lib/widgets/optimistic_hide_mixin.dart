import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

/// Firestore 서버 응답을 기다리지 않고 로컬에서 즉시 감춘 뒤(Dismissible의
/// onDismissed 등), 서버가 실제로 반영한 게 확인되면 그 로컬 오버라이드를
/// 지우는 공통 패턴을 담는다.
///
/// Dismissible은 onDismissed 콜백이 끝난 다음 프레임에는 위젯이 트리에서
/// 사라져 있기를 기대하는데, 서버 응답(스트림 갱신)을 그대로 기다리면 그
/// 사이 시간차 때문에 "A dismissed Dismissible widget is still part of the
/// tree" 오류가 난다. 그래서 로컬에서 먼저 감추되, 서버가 실제로 반영한
/// 뒤에도 오버라이드를 계속 남겨두면 그게 최신 상태 판단을 가려버리므로
/// (예: 상대가 나중에 새 메시지를 보내도 채팅방이 다시 안 뜨는 문제) 확인
/// 즉시 정리해야 한다.
mixin OptimisticHideMixin<T extends StatefulWidget> on State<T> {
  final Set<String> _locallyHiddenIds = {};

  bool isLocallyHidden(String id) => _locallyHiddenIds.contains(id);

  void hideLocally(String id) {
    setState(() => _locallyHiddenIds.add(id));
  }

  /// 서버 요청이 실패했을 때 로컬에서 감췄던 것을 되돌린다.
  void unhideLocally(String id) {
    if (mounted) setState(() => _locallyHiddenIds.remove(id));
  }

  /// 최신 문서 목록을 받을 때마다 호출한다. 목록에서 아예 사라졌거나(문서
  /// 삭제) [isConfirmedGone]이 true를 반환하는(예: clearedAt 같은 필드가
  /// 실제로 반영됨) id를 다음 프레임에 로컬 오버라이드에서 정리한다.
  /// build 도중에는 setState를 호출할 수 없어 한 프레임 미룬다.
  void reconcileLocallyHidden(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> currentDocs, {
    bool Function(QueryDocumentSnapshot<Map<String, dynamic>> doc)?
    isConfirmedGone,
  }) {
    if (_locallyHiddenIds.isEmpty) return;

    final presentIds = currentDocs.map((doc) => doc.id).toSet();
    final confirmed = _locallyHiddenIds.difference(presentIds).toSet();
    if (isConfirmedGone != null) {
      for (final doc in currentDocs) {
        if (_locallyHiddenIds.contains(doc.id) && isConfirmedGone(doc)) {
          confirmed.add(doc.id);
        }
      }
    }
    if (confirmed.isEmpty) return;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) setState(() => _locallyHiddenIds.removeAll(confirmed));
    });
  }
}
