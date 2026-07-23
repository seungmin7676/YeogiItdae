import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/lost_found_item.dart';
import '../services/error_messages.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

/// 화면: 알림 구독 관리. 저장해둔 키워드가 제목/설명에 포함되거나, 구독한
/// 카테고리의 새 글이 등록되면 알림을 받는다.
class SavedSearchesScreen extends StatelessWidget {
  const SavedSearchesScreen({super.key});

  Future<void> _addKeyword(BuildContext context, String uid) async {
    final controller = TextEditingController();
    final keyword = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(kRadiusMd),
        ),
        title: const Text('키워드 추가'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: '예: 검은색 백팩'),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('추가'),
          ),
        ],
      ),
    );
    if (keyword == null || keyword.isEmpty || !context.mounted) return;

    try {
      await FirebaseFirestore.instance.collection('savedSearches').doc(uid).set(
        {
          'keywords': FieldValue.arrayUnion([keyword]),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('키워드 추가에 실패했습니다: ${friendlyErrorMessage(e)}')),
        );
      }
    }
  }

  Future<void> _removeKeyword(
    BuildContext context,
    String uid,
    String keyword,
  ) async {
    try {
      await FirebaseFirestore.instance
          .collection('savedSearches')
          .doc(uid)
          .update({
            'keywords': FieldValue.arrayRemove([keyword]),
          });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('키워드 삭제에 실패했습니다: ${friendlyErrorMessage(e)}')),
        );
      }
    }
  }

  Future<void> _toggleCategory(
    BuildContext context,
    String uid,
    String category,
    bool subscribed,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('savedSearches').doc(uid).set(
        {
          'categories': subscribed
              ? FieldValue.arrayRemove([category])
              : FieldValue.arrayUnion([category]),
        },
        SetOptions(merge: true),
      );
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('카테고리 구독 변경에 실패했습니다: ${friendlyErrorMessage(e)}'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('알림 구독')),
      floatingActionButton: uid == null
          ? null
          : FloatingActionButton.extended(
              onPressed: () => _addKeyword(context, uid),
              tooltip: '키워드 추가',
              icon: const Icon(Icons.add_rounded, size: 20),
              label: const Text(
                '키워드 추가',
                style: TextStyle(fontWeight: FontWeight.w700),
              ),
            ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('savedSearches')
            .doc(uid ?? '_')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          final data = snapshot.data?.data();
          final keywords = List<String>.from(
            data?['keywords'] as List? ?? const [],
          );
          final subscribedCategories = Set<String>.from(
            data?['categories'] as List? ?? const [],
          );

          return ListView(
            padding: const EdgeInsets.fromLTRB(
              kPagePadding,
              20,
              kPagePadding,
              100,
            ),
            children: [
              const SectionLabel('카테고리 구독'),
              const SizedBox(height: 4),
              const Text(
                '구독한 카테고리에 새 글이 등록되면 알려드려요.',
                style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: kItemCategories.map((category) {
                  final subscribed = subscribedCategories.contains(category);
                  return SelectChip(
                    label: subscribed ? '$category ✓' : category,
                    selected: subscribed,
                    onTap: uid == null
                        ? () {}
                        : () => _toggleCategory(
                            context,
                            uid,
                            category,
                            subscribed,
                          ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 32),
              const SectionLabel('키워드 알림'),
              const SizedBox(height: 4),
              const Text(
                '저장한 키워드가 제목이나 설명에 포함된 새 글이 등록되면 알려드려요.',
                style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
              ),
              const SizedBox(height: 12),
              if (keywords.isEmpty)
                const Padding(
                  padding: EdgeInsets.symmetric(vertical: 12),
                  child: Text(
                    '저장한 키워드가 없어요.\n아래 키워드 추가 버튼으로 시작해보세요.',
                    style: TextStyle(color: AppColors.inkMuted, height: 1.5),
                  ),
                )
              else
                GroupSurface(
                  children: [
                    for (final keyword in keywords)
                      ListTile(
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 2,
                        ),
                        leading: const Icon(
                          Icons.search_rounded,
                          color: AppColors.inkMuted,
                        ),
                        title: Text(
                          keyword,
                          style: const TextStyle(fontWeight: FontWeight.w600),
                        ),
                        trailing: IconButton(
                          icon: const Icon(
                            Icons.close_rounded,
                            size: 18,
                            color: AppColors.inkMuted,
                          ),
                          tooltip: '삭제',
                          onPressed: uid == null
                              ? null
                              : () => _removeKeyword(context, uid, keyword),
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}
