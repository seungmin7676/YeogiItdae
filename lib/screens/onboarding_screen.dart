import 'package:flutter/material.dart';

import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/hallym_logo.dart';
import 'main_nav_screen.dart';

class _OnboardingPage {
  final IconData? icon;
  final String title;
  final String description;

  const _OnboardingPage({
    this.icon,
    required this.title,
    required this.description,
  });
}

const List<_OnboardingPage> _kOnboardingPages = [
  _OnboardingPage(
    title: '여기있대!에 오신 것을 환영해요',
    description: '한림대학교 캠퍼스에서 잃어버린 물건과 주운 물건을\n빠르게 찾고 전달할 수 있는 앱이에요.',
  ),
  _OnboardingPage(
    icon: Icons.search_rounded,
    title: '분실물·습득물을 둘러보세요',
    description: '홈 화면에서 카테고리와 검색으로\n원하는 물건을 빠르게 찾을 수 있어요.',
  ),
  _OnboardingPage(
    icon: Icons.edit_outlined,
    title: '주운 물건, 잃어버린 물건을 등록하세요',
    description: '사진과 함께 등록하면 주인을 찾거나\n분실물을 되찾을 확률이 높아져요.',
  ),
  _OnboardingPage(
    icon: Icons.chat_bubble_outline_rounded,
    title: '채팅으로 안전하게 연락하세요',
    description: '게시글 작성자와 실시간으로 채팅할 수 있고,\n필요하면 언제든 차단할 수 있어요.',
  ),
];

/// 화면: 앱 최초 실행 시 한 번만 보여주는 사용법 튜토리얼.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _finish() async {
    await markOnboardingSeen();
    if (!mounted) return;
    Navigator.of(context).pushReplacement(
      MaterialPageRoute(builder: (context) => const MainNavScreen()),
    );
  }

  void _next() {
    if (_index == _kOnboardingPages.length - 1) {
      _finish();
      return;
    }
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _kOnboardingPages.length - 1;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Column(
          children: [
            Align(
              alignment: Alignment.topRight,
              child: Padding(
                padding: const EdgeInsets.only(right: 8, top: 4),
                child: TextButton(
                  onPressed: _finish,
                  child: const Text(
                    '건너뛰기',
                    style: TextStyle(color: AppColors.inkMuted),
                  ),
                ),
              ),
            ),
            Expanded(
              child: PageView.builder(
                controller: _controller,
                itemCount: _kOnboardingPages.length,
                onPageChanged: (index) => setState(() => _index = index),
                itemBuilder: (context, index) {
                  final page = _kOnboardingPages[index];
                  return Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        if (page.icon == null)
                          const HallymLogo(size: 96)
                        else
                          Container(
                            width: 96,
                            height: 96,
                            alignment: Alignment.center,
                            decoration: const BoxDecoration(
                              gradient: kBrandGradient,
                              shape: BoxShape.circle,
                            ),
                            child: Icon(
                              page.icon,
                              color: Colors.white,
                              size: 40,
                            ),
                          ),
                        const SizedBox(height: 32),
                        Text(
                          page.title,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 21,
                            fontWeight: FontWeight.w800,
                            color: AppColors.ink,
                            letterSpacing: -0.3,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          page.description,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            fontSize: 14,
                            height: 1.5,
                            color: AppColors.inkMuted,
                          ),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: List.generate(_kOnboardingPages.length, (i) {
                final selected = i == _index;
                return AnimatedContainer(
                  duration: const Duration(milliseconds: 200),
                  margin: const EdgeInsets.symmetric(horizontal: 4),
                  width: selected ? 20 : 6,
                  height: 6,
                  decoration: BoxDecoration(
                    color: selected ? AppColors.primary : AppColors.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                );
              }),
            ),
            const SizedBox(height: 24),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24),
              child: ElevatedButton(
                onPressed: _next,
                child: Text(isLast ? '시작하기' : '다음'),
              ),
            ),
            const SizedBox(height: 24),
          ],
        ),
      ),
    );
  }
}
