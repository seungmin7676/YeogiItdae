import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/lost_found_item.dart';
import '../theme/app_theme.dart';
import '../widgets/feed_message.dart';
import '../widgets/item_card.dart';
import 'item_detail_sheet.dart';

/// 화면: 내가 찜한 글 모아보기
class SavedItemsScreen extends StatelessWidget {
  const SavedItemsScreen({super.key});

  void _showDetail(BuildContext context, LostFoundItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => ItemDetailSheet(item: item),
    );
  }

  // Firestore의 whereIn은 한 번에 최대 10개까지만 지원하므로 10개씩 나눠 조회한다.
  Future<List<LostFoundItem>> _fetchItems(List<String> itemIds) async {
    final items = <LostFoundItem>[];
    for (var i = 0; i < itemIds.length; i += 10) {
      final chunk = itemIds.sublist(
        i,
        (i + 10) > itemIds.length ? itemIds.length : i + 10,
      );
      final snap = await itemsCollection
          .where(FieldPath.documentId, whereIn: chunk)
          .get();
      items.addAll(snap.docs.map(LostFoundItem.fromDoc));
    }
    // 최근에 찜한 순서(itemIds 뒤쪽)가 위로 오도록 뒤집는다.
    final byId = {for (final item in items) item.id: item};
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
      appBar: AppBar(
        title: const Text('찜한 글'),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('bookmarks')
            .doc(uid ?? '_')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          final itemIds = List<String>.from(
            snapshot.data?.data()?['itemIds'] as List? ?? const [],
          );
          if (itemIds.isEmpty) {
            return const FeedMessage(
              icon: Icons.bookmark_border_rounded,
              text: '찜한 글이 없어요.',
            );
          }

          return FutureBuilder<List<LostFoundItem>>(
            future: _fetchItems(itemIds),
            builder: (context, itemsSnapshot) {
              if (!itemsSnapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }
              final items = itemsSnapshot.data!;
              if (items.isEmpty) {
                return const FeedMessage(
                  icon: Icons.bookmark_border_rounded,
                  text: '찜한 글이 없어요.',
                );
              }
              return RefreshIndicator(
                color: AppColors.primary,
                onRefresh: () => FirebaseFirestore.instance
                    .collection('bookmarks')
                    .doc(uid ?? '_')
                    .get(const GetOptions(source: Source.server)),
                child: ListView.builder(
                  padding: const EdgeInsets.all(20),
                  itemCount: items.length,
                  itemBuilder: (context, index) {
                    final item = items[index];
                    return ItemCard(
                      item: item,
                      onTap: () => _showDetail(context, item),
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
