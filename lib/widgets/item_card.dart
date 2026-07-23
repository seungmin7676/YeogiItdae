import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../models/lost_found_item.dart';
import '../theme/app_theme.dart';

/// 피드의 기본 행(row) — v3에서는 카드가 아니라 풀블리드 리스트 행이다.
/// 왼쪽에 각진 라운드 썸네일, 오른쪽에 상태 라벨 → 제목 → 메타가 타이포
/// 위계를 이룬다. 행 사이 구분은 화면 쪽에서 헤어라인([Divider])으로 만든다.
class ItemCard extends StatelessWidget {
  final LostFoundItem item;
  final VoidCallback onTap;

  /// 내 글 화면의 다중 선택 모드. 선택 UI를 카드가 직접 그려서
  /// 화면마다 좌표를 하드코딩한 오버레이를 겹치지 않아도 된다.
  final bool selectionMode;
  final bool selected;
  final VoidCallback? onLongPress;

  const ItemCard({
    super.key,
    required this.item,
    required this.onTap,
    this.selectionMode = false,
    this.selected = false,
    this.onLongPress,
  });

  static const double _thumbSize = 96;

  Widget _thumbnail() {
    Widget placeholder(IconData icon) => Container(
      width: _thumbSize,
      height: _thumbSize,
      color: AppColors.surfaceAlt,
      alignment: Alignment.center,
      child: Icon(icon, color: AppColors.inkFaint, size: 26),
    );
    return Container(
      width: _thumbSize,
      height: _thumbSize,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(kRadiusMd),
        border: Border.all(color: AppColors.line),
      ),
      child: item.imageUrls.isNotEmpty
          ? CachedNetworkImage(
              imageUrl: item.imageUrls.first,
              width: _thumbSize,
              height: _thumbSize,
              fit: BoxFit.cover,
              placeholder: (context, url) => placeholder(Icons.image_outlined),
              errorWidget: (context, url, error) =>
                  placeholder(Icons.broken_image_outlined),
            )
          : placeholder(Icons.inventory_2_outlined),
    );
  }

  @override
  Widget build(BuildContext context) {
    final metaParts = [
      item.location,
      item.authorNickname,
      if (item.createdAt != null) relativeTime(item.createdAt),
      if (item.viewCount > 0) '조회 ${item.viewCount}',
    ];
    return Material(
      color: selected ? AppColors.primaryMuted : Colors.transparent,
      child: InkWell(
        onTap: onTap,
        onLongPress: onLongPress,
        child: Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: kPagePadding,
            vertical: 14,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Opacity(opacity: item.resolved ? 0.5 : 1.0, child: _thumbnail()),
              const SizedBox(width: 14),
              Expanded(
                child: Opacity(
                  opacity: item.resolved ? 0.55 : 1.0,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 8,
                        runSpacing: 4,
                        children: [
                          StatusBadge(type: item.type),
                          Text(
                            item.category,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(
                              fontSize: 12,
                              color: AppColors.inkMuted,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          if (item.resolved)
                            const SoftBadge(
                              label: '거래완료',
                              color: AppColors.inkMuted,
                            ),
                          if (item.viewCount >= kPopularViewThreshold)
                            const SoftBadge(
                              label: '인기',
                              color: AppColors.primary,
                            ),
                          if (item.isHidden)
                            const SoftBadge(
                              label: '숨김',
                              color: AppColors.danger,
                            ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Text(
                        item.title,
                        style: const TextStyle(
                          fontSize: 15.5,
                          fontWeight: FontWeight.w700,
                          color: AppColors.ink,
                          letterSpacing: -0.3,
                          height: 1.3,
                        ),
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        metaParts.join(' · '),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                          fontSize: 12.5,
                          color: AppColors.inkFaint,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              if (selectionMode) ...[
                const SizedBox(width: 12),
                Padding(
                  padding: const EdgeInsets.only(top: 36),
                  child: AnimatedContainer(
                    duration: kMotionFast,
                    width: 22,
                    height: 22,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      color: selected ? AppColors.primary : AppColors.surface,
                      border: Border.all(
                        color: selected
                            ? AppColors.primary
                            : AppColors.lineStrong,
                        width: 1.5,
                      ),
                    ),
                    child: selected
                        ? const Icon(
                            Icons.check_rounded,
                            size: 15,
                            color: Colors.white,
                          )
                        : null,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// 옅은 틴트 배경의 상태 라벨(거래완료·인기·숨김).
class SoftBadge extends StatelessWidget {
  final String label;
  final Color color;
  final IconData? icon;

  const SoftBadge({
    super.key,
    required this.label,
    required this.color,
    this.icon,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2.5),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 11, color: color),
            const SizedBox(width: 3),
          ],
          Text(
            label,
            style: TextStyle(
              color: color,
              fontSize: 11,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.1,
            ),
          ),
        ],
      ),
    );
  }
}

/// 습득물/분실물 상태 라벨 — 배지 상자 대신 색 점 + 강한 텍스트.
/// 순백 화면에서 유일하게 색이 정보를 전달하는 자리다.
class StatusBadge extends StatelessWidget {
  final ItemType type;

  const StatusBadge({super.key, required this.type});

  @override
  Widget build(BuildContext context) {
    final isFound = type == ItemType.found;
    final color = isFound ? AppColors.found : AppColors.lost;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 6,
          height: 6,
          decoration: BoxDecoration(color: color, shape: BoxShape.circle),
        ),
        const SizedBox(width: 5),
        Text(
          isFound ? '습득물' : '분실물',
          style: TextStyle(
            color: color,
            fontSize: 12,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.1,
          ),
        ),
      ],
    );
  }
}
