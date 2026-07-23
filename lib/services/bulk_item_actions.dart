import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

/// 일괄 작업 결과. 성공/이미 삭제됨/실패/중복 실행으로 건너뜀을 구분해,
/// 화면이 "성공한 것만 선택 해제하고 실패한 것만 남겨 재시도"할 수 있게 한다.
@immutable
class BulkActionResult {
  /// 서버에 실제로 반영된 글 id.
  final List<String> succeeded;

  /// 이미 삭제되어 처리 대상이 아니게 된 글 id (재시도해도 소용없음).
  final List<String> notFound;

  /// 네트워크/권한 등 오류로 반영되지 못한 글 id (재시도 대상).
  final List<String> failed;

  /// 같은 글에 대한 이전 요청이 아직 진행 중이라 이번 요청에서 건너뛴 id.
  final List<String> skipped;

  const BulkActionResult({
    this.succeeded = const [],
    this.notFound = const [],
    this.failed = const [],
    this.skipped = const [],
  });

  bool get hasFailures => failed.isNotEmpty;
}

/// 내 글 화면의 "여러 개 선택 → 거래완료/삭제" 같은 다건 작업을 담당한다.
///
/// - 요청 시작 시 id 목록을 중복 제거한 불변 스냅샷으로 고정한다.
///   (처리 중 선택 목록이 바뀌어도 작업 대상이 바뀌지 않는다)
/// - 같은 글 id에 대한 in-flight 요청을 추적해, 버튼 연타 등으로 같은 작업이
///   다시 들어와도 이미 처리 중인 글은 건너뛴다. (UI 비활성화와 별개의
///   서비스 계층 방어)
/// - 전체를 하나의 원자적 batch로 묶지 않고 글 단위로 처리해, 한 건의
///   실패(이미 삭제된 글, legacy 문서 등)가 나머지 전체를 실패시키지 않는다.
/// - '거래완료' 업데이트는 이미 완료된 글에 다시 적용해도 같은 값을 쓰는
///   안전한 no-op이다(서버 규칙 테스트로 확인).
class BulkItemActions {
  BulkItemActions(this.collection);

  final CollectionReference<Map<String, dynamic>> collection;

  /// 현재 처리 중인 글 id. (이 인스턴스를 공유하는 화면 안에서의 방어)
  final Set<String> _inFlightIds = {};

  Future<BulkActionResult> markResolved(Iterable<String> ids) {
    return _run('markResolved', ids, (doc) => doc.update({'resolved': true}));
  }

  Future<BulkActionResult> deleteItems(Iterable<String> ids) {
    return _run('delete', ids, (doc) => doc.delete());
  }

  Future<BulkActionResult> _run(
    String opName,
    Iterable<String> ids,
    Future<void> Function(DocumentReference<Map<String, dynamic>> doc) op,
  ) async {
    // 중복 제거 + 불변 스냅샷. in-flight 예약은 await 이전(동기 구간)에
    // 끝내서, 같은 프레임에 두 번 호출돼도 두 번째 호출이 끼어들 수 없다.
    final targets = <String>[];
    final skipped = <String>[];
    for (final id in {...ids}) {
      if (_inFlightIds.add(id)) {
        targets.add(id);
      } else {
        skipped.add(id);
      }
    }

    final succeeded = <String>[];
    final notFound = <String>[];
    final failed = <String>[];
    try {
      await Future.wait(
        targets.map((id) async {
          try {
            await op(collection.doc(id));
            succeeded.add(id);
          } on FirebaseException catch (e) {
            if (e.code == 'not-found') {
              notFound.add(id);
            } else {
              failed.add(id);
            }
            debugPrint('BulkItemActions.$opName 실패 (id=$id, code=${e.code})');
          } catch (e) {
            failed.add(id);
            debugPrint('BulkItemActions.$opName 실패 (id=$id, ${e.runtimeType})');
          }
        }),
      );
    } finally {
      // 예외가 나더라도 in-flight 표시가 남아 이후 요청까지 막지 않도록
      // 반드시 정리한다.
      _inFlightIds.removeAll(targets);
    }

    return BulkActionResult(
      succeeded: succeeded,
      notFound: notFound,
      failed: failed,
      skipped: skipped,
    );
  }
}
