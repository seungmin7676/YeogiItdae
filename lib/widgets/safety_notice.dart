import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

const photoPrivacyNotice =
    '사진 속 학생증·카드번호·연락처는 가려주세요. 주인 확인에 쓸 고유한 특징은 일부 남겨두세요.';
const handoverSafetyNotice =
    '전달 전 사진에 없는 특징·분실 장소를 서로 확인하고, 교내 공개된 장소에서 만나세요. 학교 이메일 인증은 물건 소유 확인을 대신하지 않아요.';

class SafetyNotice extends StatelessWidget {
  const SafetyNotice({super.key, required this.text});
  final String text;

  @override
  Widget build(BuildContext context) => Container(
    padding: const EdgeInsets.all(12),
    decoration: BoxDecoration(
      color: AppColors.surfaceAlt,
      borderRadius: BorderRadius.circular(kRadiusMd),
    ),
    child: Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Icon(Icons.shield_outlined, size: 18, color: AppColors.inkMuted),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            text,
            style: const TextStyle(
              fontSize: 12.5,
              height: 1.5,
              color: AppColors.inkMuted,
            ),
          ),
        ),
      ],
    ),
  );
}

Future<void> showHandoverSafety(BuildContext context) => showDialog<void>(
  context: context,
  builder: (context) => AlertDialog(
    title: const Text('물건을 전달하기 전에'),
    content: const Text(
      '$handoverSafetyNotice\n\n'
      '1. 케이스·흠집·보관 물품 등 공개하지 않은 특징을 확인하세요.\n'
      '2. 휴대폰은 소유자가 직접 잠금 해제하는지 확인하세요.\n'
      '3. 신분증 사진·전체 카드번호·비밀번호를 채팅으로 요구하거나 보내지 마세요.\n'
      '4. 확인이 어렵다면 교내 담당 부서에 인계하세요.',
    ),
    actions: [
      TextButton(
        onPressed: () => Navigator.pop(context),
        child: const Text('확인'),
      ),
    ],
  ),
);
