import 'package:flutter_test/flutter_test.dart';
import 'package:latte/services/item_queries.dart';

/// 목록 화면 다섯 곳(홈 피드·내 글·작성자 글·알림·채팅 목록)이 공유하는
/// "더 보기" 판단 규칙에 대한 회귀 테스트.
///
/// 고친 버그: limit을 올리면 Firestore 쿼리가 새로 구독되는데, StreamBuilder는
/// 재구독하는 동안에도 직전 스냅샷을 그대로 들고 있다(hasData가 계속 true).
/// 예전 코드는 "데이터가 있다"는 이유만으로 곧바로 로딩 표시를 껐고, 같은
/// 이유로 문서 수가 아직 옛 페이지 크기라 "더 보기" 행 자체가 한 프레임
/// 사라졌다가 다시 나타났다.
void main() {
  group('shouldShowLoadMore', () {
    test('받은 개수가 요청한 개수와 같으면 다음 페이지가 있을 수 있다고 본다', () {
      expect(
        shouldShowLoadMore(loadedCount: 20, limit: 20, isLoadingMore: false),
        isTrue,
      );
    });

    test('받은 개수가 요청한 개수보다 적으면 마지막 페이지로 본다', () {
      expect(
        shouldShowLoadMore(loadedCount: 13, limit: 20, isLoadingMore: false),
        isFalse,
      );
    });

    test('다음 페이지를 불러오는 중에는 아직 옛 개수여도 "더 보기" 행을 유지한다', () {
      // 20개를 받은 상태에서 "더 보기"를 눌러 limit이 30이 된 직후의 프레임.
      expect(
        shouldShowLoadMore(loadedCount: 20, limit: 30, isLoadingMore: true),
        isTrue,
      );
    });

    test('목록이 비어 있고 로딩 중도 아니면 "더 보기"를 보여주지 않는다', () {
      expect(
        shouldShowLoadMore(loadedCount: 0, limit: 20, isLoadingMore: false),
        isFalse,
      );
    });
  });

  group('shouldFinishPageLoad', () {
    test('재구독 중(스냅샷이 아직 안 옴)에는 로딩 표시를 끄지 않는다', () {
      expect(
        shouldFinishPageLoad(isLoadingMore: true, hasLiveSnapshot: false),
        isFalse,
      );
    });

    test('새 스냅샷이 실제로 도착하면 로딩 표시를 끈다', () {
      expect(
        shouldFinishPageLoad(isLoadingMore: true, hasLiveSnapshot: true),
        isTrue,
      );
    });

    test('로딩 중이 아니면 스냅샷이 와도 상태를 건드리지 않는다', () {
      expect(
        shouldFinishPageLoad(isLoadingMore: false, hasLiveSnapshot: true),
        isFalse,
      );
    });
  });
}
