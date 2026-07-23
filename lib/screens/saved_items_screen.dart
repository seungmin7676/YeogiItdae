import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../models/lost_found_item.dart';
import '../theme/app_theme.dart';
import '../widgets/feed_message.dart';
import '../widgets/item_card.dart';
import '../widgets/skeleton.dart';
import 'item_detail_sheet.dart';

/// 화면: 내가 찜한 글 모아보기
class SavedItemsScreen extends StatefulWidget {
  const SavedItemsScreen({super.key});

  @override
  State<SavedItemsScreen> createState() => _SavedItemsScreenState();
}

class _SavedItemsScreenState extends State<SavedItemsScreen> {
  // build마다 새 Future를 만들면 화면이 다시 그려질 때마다 목록 전체를
  // 다시 조회(+죽은 북마크 정리 쓰기)하게 되므로, 찜 목록(itemIds)이 실제로
  // 바뀌었을 때만 새로 조회하도록 Future를 상태로 캐시한다.
  Future<List<LostFoundItem>>? _itemsFuture;
  List<String>? _fetchedForIds;

  Future<List<LostFoundItem>> _itemsFutureFor(String uid, List<String> ids) {
    if (_itemsFuture == null || !listEquals(_fetchedForIds, ids)) {
      _fetchedForIds = List.of(ids);
      _itemsFuture = _fetchItems(uid, List.of(ids));
    }
    return _itemsFuture!;
  }

  /// 오류 후 "다시 시도"나 당겨서 새로고침 시 캐시된 Future를 버리고 다시 조회한다.
  void _refetch() {
    setState(() {
      _itemsFuture = null;
      _fetchedForIds = null;
    });
  }

  // Firestore의 whereIn은 한 번에 최대 10개까지만 지원하므로 10개씩 나눠 조회한다.
  Future<List<LostFoundItem>> _fetchItems(
    String uid,
    List<String> itemIds,
  ) async {
    final items = <LostFoundItem>[];
    for (var i = 0; i < itemIds.length; i += 10) {
      final chunk = itemIds.sublist(
        i,
        (i + 10) > itemIds.length ? itemIds.length : i + 10,
      );
      final snap = await itemsCollection
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      items.addAll(LostFoundItem.fromDocs(snap.docs));
    }
    final byId = {for (final item in items) item.id: item};

    // 작성자가 삭제한 글은 더 이상 존재하지 않는데, bookmarks 배열에는 죽은
    // id로 계속 남아있어 매번 조회 대상에 끼어든다. 이번에 찾지 못한 id는
    // 본인 배열이므로 조용히 정리한다(실패해도 다음에 또 정리 시도하면
    // 되므로 치명적이지 않다).
    final missingIds = itemIds.where((id) => !byId.containsKey(id)).toList();
    if (missingIds.isNotEmpty) {
      FirebaseFirestore.instance
          .collection('bookmarks')
          .doc(uid)
          .update({'itemIds': FieldValue.arrayRemove(missingIds)})
          .catchError((_) {});
    }

    // 최근에 찜한 순서(itemIds 뒤쪽)가 위로 오도록 뒤집는다.
    return itemIds.reversed
        .map((id) => byId[id])
        .whereType<LostFoundItem>()
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('찜한 글')),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('bookmarks')
            .doc(uid ?? '_')
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FeedMessage(
              icon: Icons.error_outline_rounded,
              title: '찜한 글을 불러오지 못했어요',
              text: '네트워크 상태를 확인한 뒤 다시 시도해주세요.',
              actionLabel: '다시 시도',
              onAction: _refetch,
            );
          }
          if (!snapshot.hasData) {
            return const ItemListSkeleton();
          }
          final itemIds = List<String>.from(
            snapshot.data?.data()?['itemIds'] as List? ?? const [],
          );
          if (itemIds.isEmpty) {
            return const FeedMessage(
              icon: Icons.bookmark_border_rounded,
              title: '찜한 글이 없어요',
              text: '게시글 상세에서 북마크를 누르면\n여기에 모아 볼 수 있어요.',
            );
          }

          return FutureBuilder<List<LostFoundItem>>(
            future: _itemsFutureFor(uid ?? '_', itemIds),
            builder: (context, itemsSnapshot) {
              // 조회가 실패해도 스켈레톤에 영원히 머물지 않고 오류를 보여주고
              // 다시 시도할 수 있게 한다.
              if (itemsSnapshot.hasError) {
                return FeedMessage(
                  icon: Icons.error_outline_rounded,
                  title: '찜한 글을 불러오지 못했어요',
                  text: '네트워크 상태를 확인한 뒤 다시 시도해주세요.',
                  actionLabel: '다시 시도',
                  onAction: _refetch,
                );
              }
              if (!itemsSnapshot.hasData) {
                return const ItemListSkeleton();
              }
              final items = itemsSnapshot.data!;
              if (items.isEmpty) {
                return const FeedMessage(
                  icon: Icons.bookmark_border_rounded,
                  title: '찜한 글이 없어요',
                  text: '게시글 상세에서 북마크를 누르면\n여기에 모아 볼 수 있어요.',
                );
              }
              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () async {
                  await FirebaseFirestore.instance
                      .collection('bookmarks')
                      .doc(uid ?? '_')
                      .get(const GetOptions(source: Source.server));
                  _refetch();
                },
                child: ListView.separated(
                  padding: const EdgeInsets.only(bottom: 32),
                  itemCount: items.length,
                  separatorBuilder: (context, index) => const Divider(),
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ItemCard(
                      item: item,
                      onTap: () => showItemDetailSheet(context, item),
                    );
                  },
                ),
              );
            },
          );
        },
      ),
    );
  }
}
