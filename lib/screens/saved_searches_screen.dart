import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/lost_found_item.dart';
import '../services/error_messages.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';

/// 화면: 키워드 알림 관리. 저장해둔 키워드가 제목/설명에 포함되거나, 구독한
/// 카테고리의 새 글이 등록되면 알림을 받는다. 마이페이지의 '키워드 알림'
/// 메뉴에서 들어온다(메뉴 이름과 화면 제목을 같게 유지한다).
class SavedSearchesScreen extends StatelessWidget {
  const SavedSearchesScreen({super.key});

  /// 키워드 하나의 최대 길이와 저장 가능한 개수. 새 글이 등록될 때마다 모든
  /// 사용자의 키워드를 대조하므로(register_item_screen 참고), 한 사람이
  /// 무제한으로 쌓으면 등록 한 번의 비용이 계속 늘어난다. 알림이 사실상 전부
  /// 오게 되는 한 글자짜리 키워드도 함께 막는다.
  static const int _maxKeywordLength = 20;
  static const int _maxKeywords = 20;

  Future<void> _addKeyword(
    BuildContext context,
    String uid,
    List<String> existing,
  ) async {
    if (existing.length >= _maxKeywords) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '키워드는 최대 $_maxKeywords개까지 저장할 수 있어요. 쓰지 않는 키워드를 지워주세요.',
          ),
        ),
      );
      return;
    }

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
          maxLength: _maxKeywordLength,
          textInputAction: TextInputAction.done,
          onSubmitted: (value) => Navigator.pop(context, value.trim()),
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
    controller.dispose();
    if (keyword == null || keyword.isEmpty || !context.mounted) return;

    // 한 글자짜리 키워드는 거의 모든 글에 걸려 알림이 쏟아진다.
    if (keyword.length < 2) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('키워드는 두 글자 이상 입력해주세요.')));
      return;
    }
    if (existing.contains(keyword)) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('이미 저장한 키워드예요.')));
      return;
    }

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
    // FAB의 "키워드 추가"가 이미 저장된 개수·중복을 알아야 하므로 구독을
    // 화면 전체로 끌어올린다.
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('savedSearches')
          .doc(uid ?? '_')
          .snapshots(),
      builder: (context, snapshot) {
        final data = snapshot.data?.data();
        final keywords = List<String>.from(
          data?['keywords'] as List? ?? const [],
        );
        final subscribedCategories = Set<String>.from(
          data?['categories'] as List? ?? const [],
        );
        return Scaffold(
          backgroundColor: AppColors.bg,
          appBar: AppBar(title: const Text('키워드 알림')),
          floatingActionButton: (uid == null || !snapshot.hasData)
              ? null
              : FloatingActionButton.extended(
                  onPressed: () => _addKeyword(context, uid, keywords),
                  tooltip: '키워드 추가',
                  icon: const Icon(Icons.add_rounded, size: 20),
                  label: const Text(
                    '키워드 추가',
                    style: TextStyle(fontWeight: FontWeight.w700),
                  ),
                ),
          body: Builder(
            builder: (context) {
              if (!snapshot.hasData) {
                return const Center(
                  child: CircularProgressIndicator(color: AppColors.primary),
                );
              }

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
                      final subscribed = subscribedCategories.contains(
                        category,
                      );
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
                        style: TextStyle(
                          color: AppColors.inkMuted,
                          height: 1.5,
                        ),
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
                              style: const TextStyle(
                                fontWeight: FontWeight.w600,
                              ),
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
      },
    );
  }
}
