import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../models/lost_found_item.dart';
import '../services/error_messages.dart';
import '../theme/app_theme.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/feed_message.dart';
import 'item_detail_sheet.dart';

/// 화면: 신고 관리 (관리자 전용)
///
/// reports 컬렉션이 검토 큐다. 같은 글에 대한 여러 신고를 itemId로 묶어
/// 사유와 함께 보여주고, 관리자가 숨김 / 삭제 / 반려를 결정한다. 처리 결과는
/// 작성자와 신고자에게 알림으로 전달하고, 처리한 신고 문서는 큐에서 지운다.
class AdminReportsScreen extends StatefulWidget {
  const AdminReportsScreen({super.key});

  @override
  State<AdminReportsScreen> createState() => _AdminReportsScreenState();
}

class _AdminReportsScreenState extends State<AdminReportsScreen> {
  /// 현재 처리 중인 글 id — 연타로 같은 글에 두 번 조치가 나가지 않게 막는다.
  final Set<String> _processing = {};

  CollectionReference<Map<String, dynamic>> get _reports =>
      FirebaseFirestore.instance.collection('reports');

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('신고 관리')),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: _reports.orderBy('createdAt', descending: true).snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const FeedMessage(
              icon: Icons.error_outline_rounded,
              text: '신고를 불러오지 못했습니다.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final groups = _groupByItem(snapshot.data!.docs);
          if (groups.isEmpty) {
            return const FeedMessage(
              icon: Icons.verified_outlined,
              title: '처리할 신고가 없어요',
              text: '새로 접수된 신고가 여기에 표시돼요.',
            );
          }

          return ListView.separated(
            padding: const EdgeInsets.fromLTRB(
              kPagePadding,
              12,
              kPagePadding,
              32,
            ),
            itemCount: groups.length,
            separatorBuilder: (_, _) => const SizedBox(height: 12),
            itemBuilder: (context, index) {
              final group = groups[index];
              return _ReportGroupCard(
                group: group,
                busy: _processing.contains(group.itemId),
                onHide: () => _hide(group),
                onDelete: () => _delete(group),
                onDismiss: () => _dismiss(group),
                onOpen: () => _openItem(group.itemId),
              );
            },
          );
        },
      ),
    );
  }

  /// reports 문서들을 itemId 기준으로 묶는다. 문서가 createdAt 내림차순으로
  /// 들어오므로, 그룹의 등장 순서도 "가장 최근 신고가 있는 글"이 위가 된다.
  List<_ReportGroup> _groupByItem(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
  ) {
    final order = <String>[];
    final byItem = <String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>{};
    for (final doc in docs) {
      final itemId = doc.data()['itemId'] as String?;
      if (itemId == null) continue;
      if (!byItem.containsKey(itemId)) {
        byItem[itemId] = [];
        order.add(itemId);
      }
      byItem[itemId]!.add(doc);
    }
    return [
      for (final itemId in order) _ReportGroup(itemId, byItem[itemId]!),
    ];
  }

  Future<void> _openItem(String itemId) async {
    final messenger = ScaffoldMessenger.of(context);
    final doc = await itemsCollection.doc(itemId).get();
    if (!mounted) return;
    if (!doc.exists) {
      messenger.showSnackBar(
        const SnackBar(content: Text('이미 삭제된 게시글입니다.')),
      );
      return;
    }
    showItemDetailSheet(context, LostFoundItem.fromDoc(doc));
  }

  Future<void> _hide(_ReportGroup group) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '게시글 숨김',
      content: "'${group.itemTitle}' 게시글을 숨김 처리할까요?\n피드에서 보이지 않게 되며, 나중에 되돌릴 수 있어요.",
      confirmLabel: '숨김',
      danger: true,
    );
    if (!confirmed) return;
    await _run(group, () async {
      final batch = FirebaseFirestore.instance.batch();
      batch.update(itemsCollection.doc(group.itemId), {'hidden': true});
      _notifyAuthor(batch, group, type: 'item_hidden');
      _notifyReporters(batch, group);
      _clearReports(batch, group);
      await batch.commit();
    }, successMessage: '게시글을 숨김 처리했어요.');
  }

  Future<void> _delete(_ReportGroup group) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '게시글 삭제',
      content: "'${group.itemTitle}' 게시글을 완전히 삭제할까요?\n되돌릴 수 없어요.",
      confirmLabel: '삭제',
      danger: true,
    );
    if (!confirmed) return;
    await _run(group, () async {
      final batch = FirebaseFirestore.instance.batch();
      batch.delete(itemsCollection.doc(group.itemId));
      _notifyAuthor(batch, group, type: 'item_removed');
      _notifyReporters(batch, group);
      _clearReports(batch, group);
      await batch.commit();
    }, successMessage: '게시글을 삭제했어요.');
  }

  Future<void> _dismiss(_ReportGroup group) async {
    final confirmed = await showConfirmDialog(
      context,
      title: '신고 반려',
      content: "'${group.itemTitle}' 신고를 반려할까요?\n게시글은 그대로 유지되고, 이 신고는 큐에서 사라져요.",
      confirmLabel: '반려',
    );
    if (!confirmed) return;
    await _run(group, () async {
      final batch = FirebaseFirestore.instance.batch();
      batch.update(itemsCollection.doc(group.itemId), {'reportCount': 0});
      _clearReports(batch, group);
      await batch.commit();
    }, successMessage: '신고를 반려했어요.');
  }

  /// 실제 실행 공통부 — 처리 중 표시, 오류 스낵바, 성공 스낵바를 감싼다.
  Future<void> _run(
    _ReportGroup group,
    Future<void> Function() action, {
    required String successMessage,
  }) async {
    if (!_processing.add(group.itemId)) return;
    setState(() {});
    final messenger = ScaffoldMessenger.of(context);
    try {
      await action();
      messenger.showSnackBar(SnackBar(content: Text(successMessage)));
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('처리에 실패했습니다: ${friendlyErrorMessage(e)}')),
      );
    } finally {
      _processing.remove(group.itemId);
      if (mounted) setState(() {});
    }
  }

  void _notifyAuthor(
    WriteBatch batch,
    _ReportGroup group, {
    required String type,
  }) {
    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    if (adminUid == null || group.authorUid.isEmpty) return;
    batch.set(FirebaseFirestore.instance.collection('notifications').doc(), {
      'recipientUid': group.authorUid,
      'senderUid': adminUid,
      'type': type,
      'itemId': group.itemId,
      'itemTitle': group.itemTitle,
      'read': false,
      'createdAt': FieldValue.serverTimestamp(),
    });
  }

  void _notifyReporters(WriteBatch batch, _ReportGroup group) {
    final adminUid = FirebaseAuth.instance.currentUser?.uid;
    if (adminUid == null) return;
    for (final reporterUid in group.reporterUids) {
      if (reporterUid.isEmpty) continue;
      batch.set(FirebaseFirestore.instance.collection('notifications').doc(), {
        'recipientUid': reporterUid,
        'senderUid': adminUid,
        'type': 'report_result',
        'itemId': group.itemId,
        'itemTitle': group.itemTitle,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
      });
    }
  }

  void _clearReports(WriteBatch batch, _ReportGroup group) {
    for (final doc in group.docs) {
      batch.delete(doc.reference);
    }
  }
}

/// 같은 글에 대한 신고 묶음.
class _ReportGroup {
  final String itemId;
  final List<QueryDocumentSnapshot<Map<String, dynamic>>> docs;

  _ReportGroup(this.itemId, this.docs);

  Map<String, dynamic> get _first => docs.first.data();
  String get itemTitle => _first['itemTitle'] as String? ?? '(제목 없음)';
  String get authorUid => _first['authorUid'] as String? ?? '';
  String get authorNickname => _first['authorNickname'] as String? ?? '익명';
  int get count => docs.length;

  List<String> get reporterUids => [
    for (final d in docs) d.data()['reporterUid'] as String? ?? '',
  ];

  /// 사유별 개수 — "부적절한 내용 ×2 · 스팸/광고 ×1" 형태로 요약한다.
  String get reasonSummary {
    final counts = <String, int>{};
    for (final d in docs) {
      final reason = d.data()['reason'] as String? ?? '기타';
      counts[reason] = (counts[reason] ?? 0) + 1;
    }
    return counts.entries
        .map((e) => e.value > 1 ? '${e.key} ×${e.value}' : e.key)
        .join(' · ');
  }
}

class _ReportGroupCard extends StatelessWidget {
  final _ReportGroup group;
  final bool busy;
  final VoidCallback onHide;
  final VoidCallback onDelete;
  final VoidCallback onDismiss;
  final VoidCallback onOpen;

  const _ReportGroupCard({
    required this.group,
    required this.busy,
    required this.onHide,
    required this.onDelete,
    required this.onDismiss,
    required this.onOpen,
  });

  @override
  Widget build(BuildContext context) {
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
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: GestureDetector(
                    onTap: onOpen,
                    behavior: HitTestBehavior.opaque,
                    child: Text(
                      group.itemTitle,
                      style: const TextStyle(
                        fontSize: 15.5,
                        fontWeight: FontWeight.w700,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.danger.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    '신고 ${group.count}',
                    style: const TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: AppColors.danger,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(
              '작성자 ${group.authorNickname}',
              style: const TextStyle(fontSize: 12.5, color: AppColors.inkMuted),
            ),
            const SizedBox(height: 8),
            Text(
              group.reasonSummary,
              style: const TextStyle(
                fontSize: 13.5,
                color: AppColors.ink,
                height: 1.4,
              ),
            ),
            const Divider(height: 20),
            busy
                ? const Padding(
                    padding: EdgeInsets.symmetric(vertical: 6),
                    child: Center(
                      child: SizedBox(
                        width: 20,
                        height: 20,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: AppColors.primary,
                        ),
                      ),
                    ),
                  )
                : Row(
                    children: [
                      _ActionButton(
                        icon: Icons.visibility_off_outlined,
                        label: '숨김',
                        color: AppColors.ink,
                        onTap: onHide,
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        icon: Icons.delete_outline_rounded,
                        label: '삭제',
                        color: AppColors.danger,
                        onTap: onDelete,
                      ),
                      const SizedBox(width: 8),
                      _ActionButton(
                        icon: Icons.check_circle_outline_rounded,
                        label: '반려',
                        color: AppColors.inkMuted,
                        onTap: onDismiss,
                      ),
                    ],
                  ),
          ],
        ),
      ),
    );
  }
}

class _ActionButton extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color color;
  final VoidCallback onTap;

  const _ActionButton({
    required this.icon,
    required this.label,
    required this.color,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: OutlinedButton.icon(
        onPressed: onTap,
        icon: Icon(icon, size: 18, color: color),
        label: Text(label, style: TextStyle(color: color)),
        style: OutlinedButton.styleFrom(
          padding: const EdgeInsets.symmetric(vertical: 8),
          side: BorderSide(color: AppColors.lineStrong),
        ),
      ),
    );
  }
}
