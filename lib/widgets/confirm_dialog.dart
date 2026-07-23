import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../theme/app_theme.dart';

/// 취소/확인 두 버튼짜리 확인 다이얼로그를 띄운다. 앱 곳곳에 거의 똑같이
/// 반복되던 "정말 나가시겠습니까?/삭제하시겠습니까?" 패턴을 하나로 모았다.
/// 확인을 눌렀을 때만 true를 반환하고, 취소하거나 바깥을 눌러 닫아도(다이얼로그가
/// null을 반환하는 경우 포함) false를 반환한다.
Future<bool> showConfirmDialog(
  BuildContext context, {
  required String title,
  required String content,
  required String confirmLabel,
  String cancelLabel = '취소',
  bool danger = false,
  bool haptic = false,
}) async {
  final confirmed = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(title),
      content: Text(content),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(cancelLabel),
        ),
        TextButton(
          onPressed: () {
            if (haptic) HapticFeedback.mediumImpact();
            Navigator.pop(dialogContext, true);
          },
          child: Text(
            confirmLabel,
            style: danger ? const TextStyle(color: AppColors.danger) : null,
          ),
        ),
      ],
    ),
  );
  return confirmed == true;
}
