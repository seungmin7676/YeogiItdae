import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';

import '../models/lost_found_item.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/feed_message.dart';
import '../widgets/item_card.dart';
import '../widgets/skeleton.dart';
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: Text('${widget.authorNickname}님의 글')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return FeedMessage(
              icon: Icons.error_outline_rounded,
              title: '글을 불러오지 못했어요',
              text: '네트워크 상태를 확인한 뒤 다시 시도해주세요.',
              actionLabel: '다시 시도',
              onAction: () => setState(() {}),
            );
          }
          if (!snapshot.hasData) {
            return const ItemListSkeleton();
          }

          final docs = snapshot.data!.docs;
          final items = LostFoundItem.fromDocs(
            docs,
          ).where((item) => !item.isHidden).toList();
          final canLoadMore = docs.length == _pageSize * _loadedPages;
          if (items.isEmpty) {
            return const FeedMessage(
              icon: Icons.inbox_outlined,
              text: '이 작성자가 등록한 글이 없어요.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.only(bottom: 32),
            itemCount: items.length + (canLoadMore ? 1 : 0),
            separatorBuilder: (context, index) => const Divider(),
            itemBuilder: (context, index) {
              if (index == items.length) {
                return LoadMoreButton(
                  isLoading: false,
                  onPressed: () => setState(() => _loadedPages += 1),
                );
              }
              final item = items[index];
              return ItemCard(
                item: item,
                onTap: () => showItemDetailSheet(context, item),
              );
            },
          );
        },
      ),
    );
  }
}
