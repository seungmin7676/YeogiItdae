import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// 검색어를 입력하면 그에 맞는 항목만 남는 선택 시트를 띄운다.
/// [leadingLabel]을 주면 검색 결과와 무관하게 항상 목록 맨 위에 고정 항목을
/// 하나 더 보여준다(예: "전체", "직접 입력"). 그 항목을 선택하면 그대로
/// [leadingLabel] 문자열이 반환값으로 나오므로, 호출한 쪽에서 의미를
/// 해석해서 처리하면 된다. 아무것도 선택하지 않고 닫으면 null을 반환한다.
Future<String?> showSearchablePickerSheet({
  required BuildContext context,
  required String title,
  required List<String> options,
  String? leadingLabel,
}) {
  return showModalBottomSheet<String>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (context) => _SearchablePickerSheet(
      title: title,
      options: options,
      leadingLabel: leadingLabel,
    ),
  );
}

class _SearchablePickerSheet extends StatefulWidget {
  final String title;
  final List<String> options;
  final String? leadingLabel;

  const _SearchablePickerSheet({
    required this.title,
    required this.options,
    this.leadingLabel,
  });

  @override
  State<_SearchablePickerSheet> createState() => _SearchablePickerSheetState();
}

class _SearchablePickerSheetState extends State<_SearchablePickerSheet> {
  final _searchController = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final query = _query.trim().toLowerCase();
    final filtered = query.isEmpty
        ? widget.options
        : widget.options.where((o) => o.toLowerCase().contains(query)).toList();

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SizedBox(
        height: MediaQuery.of(context).size.height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 20),
              child: TextField(
                controller: _searchController,
                autofocus: false,
                onChanged: (value) => setState(() => _query = value),
                decoration: InputDecoration(
                  hintText: '검색',
                  prefixIcon: const Icon(
                    Icons.search_rounded,
                    color: AppColors.inkMuted,
                  ),
                  filled: true,
                  fillColor: AppColors.surface,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(color: AppColors.line),
                  ),
                  focusedBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(30),
                    borderSide: const BorderSide(
                      color: AppColors.primary,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
                children: [
                  if (widget.leadingLabel != null) ...[
                    ListTile(
                      leading: const Icon(
                        Icons.edit_outlined,
                        color: AppColors.primary,
                      ),
                      title: Text(
                        widget.leadingLabel!,
                        style: const TextStyle(
                          fontWeight: FontWeight.w700,
                          color: AppColors.primary,
                        ),
                      ),
                      onTap: () => Navigator.pop(context, widget.leadingLabel),
                    ),
                    const Divider(height: 1),
                  ],
                  if (filtered.isEmpty)
                    const Padding(
                      padding: EdgeInsets.symmetric(vertical: 24),
                      child: Center(
                        child: Text(
                          '검색 결과가 없어요.',
                          style: TextStyle(color: AppColors.inkMuted),
                        ),
                      ),
                    )
                  else
                    for (final option in filtered)
                      ListTile(
                        title: Text(option),
                        onTap: () => Navigator.pop(context, option),
                      ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
