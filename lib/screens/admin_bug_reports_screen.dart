import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/lost_found_item.dart';
import '../services/error_messages.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/feed_message.dart';

/// 화면: 버그 신고 관리 (관리자 전용)
///
/// 사용자가 마이페이지에서 보낸 bugReports 문서를 최신순으로 보여준다.
/// 내용을 확인한 뒤 '처리 완료'로 삭제하면 목록에서 사라진다. 열람/삭제
/// 권한은 firestore.rules의 isAdmin()으로 제한된다.
class AdminBugReportsScreen extends StatefulWidget {
  const AdminBugReportsScreen({super.key});

  @override
  State<AdminBugReportsScreen> createState() => _AdminBugReportsScreenState();
}

class _AdminBugReportsScreenState extends State<AdminBugReportsScreen> {
  /// 처리(삭제) 중인 문서 id — 연타로 같은 항목이 중복 삭제되지 않게 막는다.
  final Set<String> _processing = {};

  CollectionReference<Map<String, dynamic>> get _bugReports =>
      FirebaseFirestore.instance.collection('bugReports');

  Future<void> _resolve(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '처리 완료',
      content: '이 버그 신고를 목록에서 삭제할까요?',
      confirmLabel: '삭제',
      danger: true,
    );
    if (!confirmed || !mounted) return;
    if (!_processing.add(doc.id)) return;
    setState(() {});
    final messenger = ScaffoldMessenger.of(context);
    try {
      await doc.reference.delete();
      messenger.showSnackBar(const SnackBar(content: Text('처리 완료했어요.')));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('삭제에 실패했습니다: ${friendlyErrorMessage(e)}')),
      );
    } finally {
      _processing.remove(doc.id);
      if (mounted) setState(() {});
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('버그 신고 관리')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _bugReports.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const FeedMessage(
              icon: Icons.error_outline_rounded,
              text: '버그 신고를 불러오지 못했습니다.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }
          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const FeedMessage(
              icon: Icons.check_circle_outline_rounded,
              title: '처리할 버그 신고가 없어요',
              text: '사용자가 보낸 버그 신고가 여기에 표시돼요.',
            );
          }
          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              kPagePadding,
              12,
              kPagePadding,
              32,
            ),
            itemCount: docs.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final doc = docs[index];
              return _BugReportCard(
                doc: doc,
                busy: _processing.contains(doc.id),
                onResolve: () => _resolve(doc),
              );
            },
          );
        },
      ),
    );
  }
}

class _BugReportCard extends StatelessWidget {
  final QueryDocumentSnapshot<Map<String, dynamic>> doc;
  final bool busy;
  final VoidCallback onResolve;

  const _BugReportCard({
    required this.doc,
    required this.busy,
    required this.onResolve,
  });

  @override
  Widget build(BuildContext context) {
    final data = doc.data();
    final content = data['content'] as String? ?? '';
    final nickname = data['reporterNickname'] as String? ?? '';
    final email = data['reporterEmail'] as String? ?? '';
    final createdAt = (data['createdAt'] as Timestamp?)?.toDate();
    final who = [
      if (nickname.isNotEmpty) nickname,
      if (email.isNotEmpty) email,
    ].join(' · ');

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(kRadiusLg),
        border: Border.all(color: AppColors.line),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              content,
              style: const TextStyle(
                fontSize: 14.5,
                color: AppColors.ink,
                height: 1.45,
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: Text(
                    [
                      if (who.isNotEmpty) who,
                      if (createdAt != null) relativeTime(createdAt),
                    ].join('  ·  '),
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                    ),
                  ),
                ),
                if (email.isNotEmpty)
                  IconButton(
                    icon: const Icon(
                      Icons.copy_rounded,
                      size: 16,
                      color: AppColors.inkMuted,
                    ),
                    tooltip: '이메일 복사',
                    visualDensity: VisualDensity.compact,
                    onPressed: () async {
                      await Clipboard.setData(ClipboardData(text: email));
                      if (context.mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(content: Text('이메일을 복사했어요.')),
                        );
                      }
                    },
                  ),
              ],
            ),
            const Divider(height: 16),
            Align(
              alignment: Alignment.centerRight,
              child: busy
                  ? const Padding(
                      padding: EdgeInsets.all(6),
                      child: SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                    )
                  : TextButton.icon(
                      onPressed: onResolve,
                      icon: const Icon(
                        Icons.check_circle_outline_rounded,
                        size: 18,
                      ),
                      label: const Text('처리 완료'),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
