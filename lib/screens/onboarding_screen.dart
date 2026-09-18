import 'package:flutter/material.dart';

import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/hallym_logo.dart';

class _OnboardingPage {
  final String eyebrow;
  final String title;
  final String description;
  final String badge;
  final IconData icon;
  final Color accent;
  final List<String> tags;

  const _OnboardingPage({
    required this.eyebrow,
    required this.title,
    required this.description,
    required this.badge,
    required this.icon,
    required this.accent,
    required this.tags,
  });
}

const List<_OnboardingPage> _kOnboardingPages = [
  _OnboardingPage(
    eyebrow: 'WELCOME',
    title: '캠퍼스의 잃어버린 물건을\n더 빠르게 찾아보세요',
    description: '한림대학교 구성원이 함께 분실물과 습득물을\n찾고 전달하는 안전한 캠퍼스 커뮤니티예요.',
    badge: '한림대학교 분실물 커뮤니티',
    icon: Icons.location_searching_rounded,
    accent: AppColors.primary,
    tags: ['교내 전용', '빠른 검색'],
  ),
  _OnboardingPage(
    eyebrow: 'FIND',
    title: '검색과 필터로\n원하는 물건만 한눈에',
    description: '습득물·분실물 종류와 카테고리, 장소를 골라\n필요한 게시글을 빠르게 확인할 수 있어요.',
    badge: '찾고 싶은 조건만 선택',
    icon: Icons.search_rounded,
    accent: AppColors.primary,
    tags: ['전자기기', '지갑·카드', '가방'],
  ),
  _OnboardingPage(
    eyebrow: 'SHARE',
    title: '사진과 위치를 더해\n발견 가능성을 높여보세요',
    description: '물건의 특징과 발견 장소를 간단히 등록하면\n주인을 찾거나 내 물건을 되찾기 쉬워져요.',
    badge: '몇 번의 터치로 간편 등록',
    icon: Icons.add_a_photo_outlined,
    accent: AppColors.found,
    tags: ['사진 첨부', '장소 선택'],
  ),
  _OnboardingPage(
    eyebrow: 'CONNECT',
    title: '안전한 1:1 채팅으로\n전달 방법을 정하세요',
    description: '게시글 작성자와 바로 대화하고 약속을 정해보세요.\n불편한 사용자는 언제든 차단할 수 있어요.',
    badge: '필요한 정보만 안전하게',
    icon: Icons.chat_bubble_outline_rounded,
    accent: AppColors.primary,
    tags: ['실시간 채팅', '사용자 차단'],
  ),
];

/// 앱 최초 실행 시 한 번 보여주는 사용법 안내.
/// 앱의 잉크 에디토리얼 디자인과 같은 흰 캔버스, 회백색 정보 면,
/// 알약 버튼과 제한적인 포인트 컬러를 사용한다.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinished;
  final String uid;
  final bool isReplay;

  const OnboardingScreen({
    super.key,
    required this.uid,
    required this.onFinished,
    this.isReplay = false,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;
  bool _dontShowAgain = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    if (!widget.isReplay && _dontShowAgain) {
      await markOnboardingSeen(widget.uid);
    }
    if (!mounted) return;
    widget.onFinished();
  }

  void _next() {
    if (_index == _kOnboardingPages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(duration: kMotionStandard, curve: Curves.easeOutCubic);
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _kOnboardingPages.length - 1;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 8, 12, 4),
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final textScale = MediaQuery.textScalerOf(context).scale(1);
                  final compactHeader =
                      constraints.maxWidth < 360 && textScale > 1.4;
                  return Row(
                    children: [
                      const HallymLogo(size: 24),
                      if (!compactHeader) ...[
                        const SizedBox(width: 10),
                        const Text(
                          '여기있대!',
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            letterSpacing: -0.4,
                          ),
                        ),
                      ],
                      const Spacer(),
                      TextButton(
                        key: const ValueKey('onboarding-close-button'),
                        onPressed: _finish,
                        style: TextButton.styleFrom(
                          foregroundColor: AppColors.inkMuted,
                          backgroundColor: AppColors.surfaceAlt,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 8,
                          ),
                          minimumSize: Size.zero,
                          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          shape: const StadiumBorder(),
                        ),
                        child: Text(
                          widget.isReplay ? '닫기' : '건너뛰기',
                          style: const TextStyle(
                            fontSize: 12.5,
                            fontWeight: FontWeight.w700,
                          ),
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _kOnboardingPages.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) => _OnboardingPageView(
                  page: _kOnboardingPages[index],
                  index: index,
                ),
              ),
            ),
            Container(
              decoration: const BoxDecoration(
                color: AppColors.surface,
                border: Border(top: BorderSide(color: AppColors.line)),
              ),
              padding: const EdgeInsets.fromLTRB(20, 12, 20, 18),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: List.generate(
                      _kOnboardingPages.length,
                      (index) => AnimatedContainer(
                        key: ValueKey('onboarding-indicator-$index'),
                        duration: kMotionFast,
                        width: index == _index ? 24 : 7,
                        height: 7,
                        margin: const EdgeInsets.symmetric(horizontal: 3),
                        decoration: BoxDecoration(
                          color: index == _index
                              ? AppColors.primary
                              : AppColors.lineStrong,
                          borderRadius: BorderRadius.circular(kRadiusPill),
                        ),
                      ),
                    ),
                  ),
                  if (!widget.isReplay) ...[
                    const SizedBox(height: 10),
                    Semantics(
                      checked: _dontShowAgain,
                      label: '다음부터 보지 않기',
                      child: InkWell(
                        onTap: () =>
                            setState(() => _dontShowAgain = !_dontShowAgain),
                        borderRadius: BorderRadius.circular(kRadiusMd),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              ExcludeSemantics(
                                child: IgnorePointer(
                                  child: Checkbox(
                                    value: _dontShowAgain,
                                    activeColor: AppColors.primary,
                                    visualDensity: VisualDensity.compact,
                                    materialTapTargetSize:
                                        MaterialTapTargetSize.shrinkWrap,
                                    onChanged: (_) {},
                                  ),
                                ),
                              ),
                              const SizedBox(width: 2),
                              const Flexible(
                                child: Text(
                                  '다음부터 보지 않기',
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: AppColors.inkMuted,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  ],
                  const SizedBox(height: 8),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      key: const ValueKey('onboarding-next-button'),
                      onPressed: _next,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            isLast
                                ? widget.isReplay
                                      ? '튜토리얼 닫기'
                                      : '여기있대! 시작하기'
                                : '다음',
                          ),
                          const SizedBox(width: 8),
                          Icon(
                            isLast
                                ? Icons.check_rounded
                                : Icons.arrow_forward_rounded,
                            size: 19,
                          ),
                        ],
                      ),
                    ),
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

class _OnboardingPageView extends StatelessWidget {
  final _OnboardingPage page;
  final int index;

  const _OnboardingPageView({required this.page, required this.index});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const verticalPadding = 20.0;
        final minimumHeight = constraints.maxHeight > verticalPadding * 2
            ? constraints.maxHeight - verticalPadding * 2
            : 0.0;
        return SingleChildScrollView(
          padding: const EdgeInsets.symmetric(
            horizontal: kPagePadding,
            vertical: verticalPadding,
          ),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: minimumHeight),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kFormMaxWidth),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FeaturePreview(page: page, index: index),
                    const SizedBox(height: 28),
                    Text(
                      page.eyebrow,
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: page.accent,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 2.2,
                      ),
                    ),
                    const SizedBox(height: 12),
                    Text(
                      page.title,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 27,
                        fontWeight: FontWeight.w800,
                        height: 1.32,
                        color: AppColors.ink,
                        letterSpacing: -0.6,
                      ),
                    ),
                    const SizedBox(height: 14),
                    Text(
                      page.description,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 14.5,
                        height: 1.65,
                        color: AppColors.inkMuted,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FeaturePreview extends StatelessWidget {
  final _OnboardingPage page;
  final int index;

  const _FeaturePreview({required this.page, required this.index});

  @override
  Widget build(BuildContext context) {
    final scaledCaption = MediaQuery.textScalerOf(context).scale(12);
    final previewHeight = (190 + (scaledCaption - 12) * 4).clamp(190.0, 270.0);
    return Container(
      height: previewHeight,
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.surfaceAlt,
        borderRadius: BorderRadius.circular(kRadiusXl),
      ),
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Positioned(
            top: 20,
            left: 22,
            child: Text(
              '0${index + 1}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w800,
                color: page.accent,
                letterSpacing: 1.4,
              ),
            ),
          ),
          Center(
            child: Container(
              width: 94,
              height: 94,
              decoration: BoxDecoration(
                color: AppColors.surface,
                shape: BoxShape.circle,
                border: Border.all(color: AppColors.line),
              ),
              child: Icon(page.icon, size: 42, color: page.accent),
            ),
          ),
          Positioned(
            top: 18,
            left: 54,
            right: 18,
            child: Align(
              alignment: Alignment.centerRight,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: AppColors.surface,
                  borderRadius: BorderRadius.circular(kRadiusPill),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.check_circle_rounded,
                      size: 14,
                      color: page.accent,
                    ),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        page.badge,
                        textAlign: TextAlign.right,
                        style: const TextStyle(
                          fontSize: 11.5,
                          color: AppColors.inkMuted,
                          fontWeight: FontWeight.w700,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Positioned(
            left: 18,
            right: 18,
            bottom: 16,
            child: Wrap(
              alignment: WrapAlignment.center,
              spacing: 7,
              runSpacing: 6,
              children: [
                for (final tag in page.tags)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 11,
                      vertical: 7,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.surface,
                      borderRadius: BorderRadius.circular(kRadiusPill),
                    ),
                    child: Text(
                      tag,
                      style: const TextStyle(
                        fontSize: 11.5,
                        color: AppColors.ink,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
