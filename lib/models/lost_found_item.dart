import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';

/// 글 종류
enum ItemType {
  found,
  lost;

  static ItemType fromValue(String value) => ItemType.values.firstWhere(
    (e) => e.name == value,
    orElse: () => ItemType.found,
  );
}

/// Firestore의 'items' 컬렉션 레퍼런스
final CollectionReference<Map<String, dynamic>> itemsCollection =
    FirebaseFirestore.instance.collection('items');

/// 주어진 시각을 "방금 전 / N분 전 / N시간 전 / 어제 / N일 전 / 날짜" 형태로 표시한다.
String relativeTime(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return '방금 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  if (diff.inDays == 1) return '어제';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  return '${time.year}.${time.month.toString().padLeft(2, '0')}.${time.day.toString().padLeft(2, '0')}';
}

/// 물품 카테고리 목록 ('전체'는 필터용이며 게시글 카테고리로는 쓰이지 않음).
const List<String> kItemCategories = [
  '전자기기',
  '지갑/카드/현금',
  '가방',
  '의류',
  '도서/문구',
  '액세서리',
  '기타',
];

/// 캠퍼스 건물/장소 목록 (등록 폼의 장소 선택, 홈 피드의 장소 필터 공용).
const List<String> kLocations = [
  '(1) 공학관',
  '(2) 대학본부-인문1관',
  '(3) 의학관',
  '(4) 인문2관',
  '(5) 대학본부별관',
  '(6) 실험동물센터',
  '(7) 자연과학관',
  '(8) 생명과학관',
  '(9) Campus Life Center',
  '(10) 사회경영1관',
  '(11) 일송아트홀',
  '(12) 창업보육센터',
  '(13) 사회경영2관',
  '(14) 국제관',
  '(15) 국제회의관',
  '(16) 기초교육관',
  '(17) 일송창의비전관',
  '(18) 한림레크리에이션센터',
  '(19) 학군단',
  '(20) 실내테니스장',
  '(21) 한림중개의과학연구원',
  '(22) 산학협력관',
  '(23) 도헌글로벌스쿨',
  '(24) 학생생활관 1관',
  '(25) 학생생활관 2관',
  '(26) 학생생활관 3관',
  '(27) 학생생활관 4관',
  '(28) 학생생활관 5관',
  '(29) 학생생활관 6관',
  '(30) 학생생활관 7관',
  '(31) 학생생활관 8관',
  '(32) 체육 기자재실',
  '(33) H Stadium',
  '(34) IL Song Stadium',
  '(35) 씨름장',
  '(36) 온실',
  '(37) 한림대학교 춘천성심병원',
];

/// 신고가 이 횟수 이상 누적되면 일반 피드에서 자동으로 숨긴다.
const int kReportThreshold = 3;

/// 조회수가 이 값 이상이면 목록에 "인기" 배지를 붙인다.
const int kPopularViewThreshold = 20;

/// 분실물/습득물 게시글 데이터 모델
class LostFoundItem {
  final String? id;
  final String title;
  final String description;
  final String location;
  final String locationDetail;
  final ItemType type;
  final String category;
  final String authorUid;
  final String authorNickname;
  final bool resolved;
  final List<String> imageUrls;
  final DateTime? createdAt;
  final int reportCount;
  final int viewCount;

  bool get isHidden => reportCount >= kReportThreshold;

  LostFoundItem({
    this.id,
    required this.title,
    this.description = '',
    required this.location,
    this.locationDetail = '',
    required this.type,
    this.category = '기타',
    required this.authorUid,
    required this.authorNickname,
    this.resolved = false,
    this.imageUrls = const [],
    this.createdAt,
    this.reportCount = 0,
    this.viewCount = 0,
  });

  factory LostFoundItem.fromDoc(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? const {};
    final urlsField = data['imageUrls'] as List?;
    final legacyUrl = data['imageUrl'] as String?;
    final imageUrls = urlsField != null
        ? urlsField.whereType<String>().toList()
        : (legacyUrl != null ? [legacyUrl] : <String>[]);
    return LostFoundItem(
      id: doc.id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      location: data['location'] as String? ?? '',
      locationDetail: data['locationDetail'] as String? ?? '',
      type: ItemType.fromValue(data['type'] as String? ?? 'found'),
      category: data['category'] as String? ?? '기타',
      authorUid: data['authorUid'] as String? ?? '',
      authorNickname: data['authorNickname'] as String? ?? '익명',
      resolved: data['resolved'] as bool? ?? false,
      imageUrls: imageUrls,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      reportCount: (data['reportCount'] as num?)?.toInt() ?? 0,
      viewCount: (data['viewCount'] as num?)?.toInt() ?? 0,
    );
  }

  /// 목록 스냅샷의 문서들을 모델로 변환하되, 문서 하나가 손상돼 있어도
  /// (예: 필드 타입이 예상과 다른 legacy/비정상 데이터) 그 한 건 때문에
  /// 전체 목록 화면이 통째로 깨지지 않도록 문서 단위로 격리한다.
  /// 변환에 실패한 문서는 어떤 문서가 왜 실패했는지 로그만 남기고 건너뛴다.
  static List<LostFoundItem> fromDocs(
    Iterable<DocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final items = <LostFoundItem>[];
    for (final doc in docs) {
      try {
        items.add(LostFoundItem.fromDoc(doc));
      } catch (e) {
        debugPrint('items/${doc.id} 문서 변환 실패, 목록에서 제외: $e');
      }
    }
    return items;
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'location': location,
      'locationDetail': locationDetail,
      'type': type.name,
      'category': category,
      'authorUid': authorUid,
      'authorNickname': authorNickname,
      'resolved': resolved,
      'imageUrls': imageUrls,
      'reportCount': 0,
      'viewCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'title': title,
      'description': description,
      'location': location,
      'locationDetail': locationDetail,
      'type': type.name,
      'category': category,
      'resolved': resolved,
      'imageUrls': imageUrls,
    };
  }
}

/// 이번 앱 세션에서 이미 조회수를 올린 게시글 id 모음 (중복 카운트 방지).
final Set<String> _viewedItemIdsThisSession = {};

/// 게시글 상세를 열 때 조회수를 1 증가시킨다. 작성자 본인의 조회는 세지 않고,
/// 같은 글을 이번 세션에서 여러 번 열어도 한 번만 센다.
void incrementItemViewCount(LostFoundItem item) {
  final myUid = FirebaseAuth.instance.currentUser?.uid;
  final itemId = item.id;
  if (myUid == null || myUid == item.authorUid || itemId == null) return;
  if (!_viewedItemIdsThisSession.add(itemId)) return;
  itemsCollection
      .doc(itemId)
      .update({'viewCount': FieldValue.increment(1)})
      .catchError((_) {});
}
