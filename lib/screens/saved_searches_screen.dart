import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/lost_found_item.dart';
import '../theme/app_theme.dart';

/// 화면: 알림 구독 관리. 저장해둔 키워드가 제목/설명에 포함되거나, 구독한
/// 카테고리의 새 글이 등록되면 알림을 받는다.
class SavedSearchesScreen extends StatelessWidget {
  const SavedSearchesScreen({super.key});

  Future<void> _addKeyword(BuildContext context, String uid) async {
    final controller = TextEditingController();
    final keyword = await showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('키워드 추가에 실패했습니다: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('키워드 삭제에 실패했습니다: $e')));
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('카테고리 구독 변경에 실패했습니다: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('알림 구독'),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      floatingActionButton: uid == null
          ? null
          : FloatingActionButton(
              onPressed: () => _addKeyword(context, uid),
              tooltip: '키워드 추가',
              child: const Icon(Icons.add_rounded),
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
            padding: const EdgeInsets.fromLTRB(20, 16, 20, 100),
            children: [
              const Text(
                '카테고리 구독',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
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
                  return FilterChip(
                    label: Text(category),
                    selected: subscribed,
                    onSelected: uid == null
                        ? null
                        : (_) => _toggleCategory(
                            context,
                            uid,
                            category,
                            subscribed,
                          ),
                    selectedColor: AppColors.primary.withValues(alpha: 0.15),
                    checkmarkColor: AppColors.primary,
                    labelStyle: TextStyle(
                      color: subscribed
                          ? AppColors.primary
                          : AppColors.inkMuted,
                      fontWeight: subscribed
                          ? FontWeight.w700
                          : FontWeight.w500,
                    ),
                    backgroundColor: AppColors.surface,
                    side: BorderSide(
                      color: subscribed ? AppColors.primary : AppColors.line,
                    ),
                  );
                }).toList(),
              ),
              const SizedBox(height: 28),
              const Text(
                '키워드 알림',
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.w700),
              ),
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
                    '저장한 키워드가 없어요. 오른쪽 아래 + 버튼으로 추가해보세요.',
                    style: TextStyle(color: AppColors.inkMuted),
                  ),
                )
              else
                for (final keyword in keywords)
                  Card(
                    margin: const EdgeInsets.only(bottom: 12),
                    elevation: 0,
                    color: AppColors.surface,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: AppColors.line),
                    ),
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 4,
                      ),
                      leading: const Icon(
                        Icons.search_rounded,
                        color: AppColors.primary,
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
                  ),
            ],
          );
        },
      ),
    );
  }
}
