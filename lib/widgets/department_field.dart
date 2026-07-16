import 'package:flutter/material.dart';

import '../models/department.dart';
import '../theme/app_theme.dart';
import 'searchable_picker_sheet.dart';

const String _kManualEntryLabel = '직접 입력';

/// 학과 입력 필드. 탭하면 검색 가능한 학과 목록 시트가 뜨고, 맨 위의
/// "직접 입력"을 고르면 목록에 없는 학과명을 자유롭게 타이핑할 수 있는
/// 일반 입력창으로 바뀐다(오른쪽 아이콘으로 언제든 목록 선택으로 되돌아갈 수 있음).
class DepartmentField extends StatefulWidget {
  final TextEditingController controller;
  final String? Function(String?)? validator;

  const DepartmentField({super.key, required this.controller, this.validator});

  @override
  State<DepartmentField> createState() => _DepartmentFieldState();
}

class _DepartmentFieldState extends State<DepartmentField> {
  final _focusNode = FocusNode();
  late bool _isFreeform =
      widget.controller.text.isNotEmpty &&
      !kDepartments.contains(widget.controller.text);

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  Future<void> _openPicker() async {
    final result = await showSearchablePickerSheet(
      context: context,
      title: '학과 선택',
      options: kDepartments,
      leadingLabel: _kManualEntryLabel,
    );
    if (result == null) return;
    if (result == _kManualEntryLabel) {
      setState(() {
        _isFreeform = true;
        widget.controller.clear();
      });
      _focusNode.requestFocus();
    } else {
      setState(() {
        _isFreeform = false;
        widget.controller.text = result;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      controller: widget.controller,
      focusNode: _focusNode,
      readOnly: !_isFreeform,
      validator: widget.validator,
      onTap: _isFreeform ? null : _openPicker,
      decoration: appInputDecoration(
        '학과',
        hint: _isFreeform ? '학과명을 입력해주세요' : '탭하여 선택',
        suffixIcon: IconButton(
          tooltip: _isFreeform ? '목록에서 선택' : '직접 입력',
          icon: Icon(
            _isFreeform ? Icons.list_alt_rounded : Icons.edit_outlined,
            color: AppColors.inkMuted,
          ),
          onPressed: _openPicker,
        ),
      ),
    );
  }
}
