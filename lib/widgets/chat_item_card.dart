import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../theme/app_theme.dart';
import 'item_card.dart';

class ChatItemCard extends StatelessWidget {
  const ChatItemCard({
    super.key,
    required this.title,
    required this.status,
    this.imageUrl,
    this.onOpen,
  });

  final String title;
  final String status;
  final String? imageUrl;
  final VoidCallback? onOpen;

  @override
  Widget build(BuildContext context) {
    final statusColor = status == '게시글 삭제됨'
        ? AppColors.inkMuted
        : status == '전달 완료'
        ? AppColors.found
        : AppColors.primary;
    final placeholder = Container(
      width: 52,
      height: 52,
      color: AppColors.surfaceAlt,
      child: const Icon(Icons.inventory_2_outlined, color: AppColors.inkFaint),
    );
    return Material(
      color: AppColors.surface,
      child: InkWell(
        onTap: onOpen,
        child: Container(
          padding: const EdgeInsets.symmetric(
            horizontal: kPagePadding,
            vertical: 12,
          ),
          decoration: const BoxDecoration(
            border: Border(bottom: BorderSide(color: AppColors.line)),
          ),
          child: Row(
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(kRadiusSm),
                child: imageUrl == null || imageUrl!.isEmpty
                    ? placeholder
                    : CachedNetworkImage(
                        imageUrl: imageUrl!,
                        width: 52,
                        height: 52,
                        fit: BoxFit.cover,
                        memCacheWidth:
                            (52 * MediaQuery.devicePixelRatioOf(context))
                                .round(),
                        placeholder: (_, _) => placeholder,
                        errorWidget: (_, _, _) => placeholder,
                      ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title.trim().isEmpty ? '게시글 정보 없음' : title,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 6),
                    Wrap(
                      spacing: 10,
                      runSpacing: 4,
                      crossAxisAlignment: WrapCrossAlignment.center,
                      children: [
                        SoftBadge(label: status, color: statusColor),
                        if (onOpen != null)
                          const Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Text(
                                '게시글 보기',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: AppColors.primary,
                                ),
                              ),
                              Icon(
                                Icons.chevron_right_rounded,
                                size: 16,
                                color: AppColors.primary,
                              ),
                            ],
                          ),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
