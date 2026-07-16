import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lost_found_item.dart';
import '../theme/app_theme.dart';
import '../widgets/feed_message.dart';
import '../widgets/item_card.dart';
import 'item_detail_sheet.dart';

/// 화면: 특정 작성자가 등록한 다른 글 모아보기
class AuthorPostsScreen extends StatefulWidget {
  final String authorUid;
  final String authorNickname;

  const AuthorPostsScreen({
    super.key,
    required this.authorUid,
    required this.authorNickname,
  });

  @override
  State<AuthorPostsScreen> createState() => _AuthorPostsScreenState();
}

class _AuthorPostsScreenState extends State<AuthorPostsScreen> {
  static const int _pageSize = 20;
  int _loadedPages = 1;

  Query<Map<String, dynamic>> get _query => itemsCollection
      .where('authorUid', isEqualTo: widget.authorUid)
      .orderBy('createdAt', descending: true)
      .limit(_pageSize * _loadedPages);

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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text('${widget.authorNickname}님의 글'),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const FeedMessage(
              icon: Icons.error_outline_rounded,
              text: '글을 불러오지 못했습니다.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final docs = snapshot.data!.docs;
          final items = docs
              .map(LostFoundItem.fromDoc)
              .where((item) => !item.isHidden)
              .toList();
          final canLoadMore = docs.length == _pageSize * _loadedPages;
          if (items.isEmpty) {
            return const FeedMessage(
              icon: Icons.inbox_outlined,
              text: '등록한 글이 없어요.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: items.length + (canLoadMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == items.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _loadedPages += 1),
                      child: const Text('더 보기'),
                    ),
                  ),
                );
              }
              final item = items[index];
              return ItemCard(
                item: item,
                onTap: () => _showDetail(context, item),
              );
            },
          );
        },
      ),
    );
  }
}
