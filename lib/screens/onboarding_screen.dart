import 'package:flutter/material.dart';

import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import '../widgets/hallym_logo.dart';

class _OnboardingPage {
  final String title;
  final String description;

  const _OnboardingPage({required this.title, required this.description});
}

const List<_OnboardingPage> _kOnboardingPages = [
  _OnboardingPage(
    title: '여기있대!에\n오신 것을 환영해요',
    description: '한림대학교 캠퍼스에서 잃어버린 물건과 주운 물건을\n빠르게 찾고 전달할 수 있는 앱이에요.',
  ),
  _OnboardingPage(
    title: '분실물·습득물을\n둘러보세요',
    description: '홈 화면에서 카테고리와 검색으로\n원하는 물건을 빠르게 찾을 수 있어요.',
  ),
  _OnboardingPage(
    title: '물건을 등록하고\n주인을 찾아주세요',
    description: '사진과 함께 등록하면 주인을 찾거나\n분실물을 되찾을 확률이 높아져요.',
  ),
  _OnboardingPage(
    title: '채팅으로\n안전하게 연락하세요',
    description: '게시글 작성자와 실시간으로 채팅할 수 있고,\n필요하면 언제든 차단할 수 있어요.',
  ),
];

/// 화면: 앱 최초 실행 시 한 번만 보여주는 사용법 튜토리얼.
/// 대각선 컬러 블록 + 좌측 정렬 타이포 + 얇은 진행바 스타일.
class OnboardingScreen extends StatefulWidget {
  final VoidCallback onFinished;
  final String uid;

  const OnboardingScreen({
    super.key,
    required this.uid,
    required this.onFinished,
  });

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _index = 0;

  /// 기본값은 "다시 보지 않기". 사용법 튜토리얼은 한 번 보면 충분한데,
  /// 기본이 꺼짐이면 체크를 놓친 대부분의 사용자가 로그인할 때마다 같은
  /// 화면을 네 장씩 다시 넘겨야 했다. 다시 보고 싶은 사람만 해제하면 된다.
  bool _dontShowAgain = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Color get _accent => _index.isEven ? AppColors.primary : AppColors.accent;

  Future<void> _finish() async {
    if (_dontShowAgain) {
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
    _controller.nextPage(
      duration: const Duration(milliseconds: 260),
      curve: Curves.easeOut,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isLast = _index == _kOnboardingPages.length - 1;
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: Stack(
        children: [
          // 대각선 컬러 블록 (좌상단)
          Positioned(
            top: 0,
            left: 0,
            child: ClipPath(
              clipper: _DiagonalClipper(),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                width: 220,
                height: 220,
                color: _accent,
              ),
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 8, 16, 0),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const HallymLogo(size: 28),
                      TextButton(
                        onPressed: _finish,
                        child: const Text(
                          '건너뛰기',
                          style: TextStyle(
                            color: AppColors.inkMuted,
                            fontWeight: FontWeight.w700,
                            fontSize: 12.5,
                          ),
                        ),
                      ),
                    ],
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
                        padding: const EdgeInsets.symmetric(horizontal: 28),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Text(
                              '0${index + 1} — 0${_kOnboardingPages.length}',
                              style: TextStyle(
                                fontSize: 12,
                                fontWeight: FontWeight.w800,
                                letterSpacing: 3,
                                color: _accent,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Text(
                              page.title,
                              style: const TextStyle(
                                fontSize: 27,
                                fontWeight: FontWeight.w800,
                                height: 1.38,
                                color: AppColors.ink,
                                letterSpacing: -0.5,
                              ),
                            ),
                            const SizedBox(height: 18),
                            Container(
                              width: 36,
                              height: 4,
                              decoration: BoxDecoration(
                                color: _accent,
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            const SizedBox(height: 18),
                            Text(
                              page.description,
                              style: const TextStyle(
                                fontSize: 14,
                                height: 1.75,
                                color: AppColors.inkMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      );
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 8,
                    vertical: 4,
                  ),
                  // 탭 처리는 바깥 InkWell이 맡고 Checkbox는 표시용이므로,
                  // 스크린 리더에는 이 영역 전체를 하나의 체크박스로 알린다.
                  child: Semantics(
                    checked: _dontShowAgain,
                    label: '다음부터 보지 않기',
                    child: InkWell(
                      onTap: () =>
                          setState(() => _dontShowAgain = !_dontShowAgain),
                      borderRadius: BorderRadius.circular(8),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 4,
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
                            const SizedBox(width: 4),
                            const Text(
                              '다음부터 보지 않기',
                              style: TextStyle(
                                fontSize: 13,
                                color: AppColors.inkMuted,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.fromLTRB(28, 0, 28, 28),
                  child: Column(
                    children: [
                      // 얇은 진행바
                      Stack(
                        children: [
                          Container(
                            height: 2,
                            decoration: BoxDecoration(
                              color: AppColors.line,
                              borderRadius: BorderRadius.circular(1),
                            ),
                          ),
                          // 진행 길이는 화면 폭에서 어림잡지 않고 트랙 폭을
                          // 기준으로 잡는다. 예전에는 화면 폭의 86%로 계산해
                          // 좁은 기기에서 마지막 장의 막대가 트랙 밖으로
                          // 삐져나가 잘렸다.
                          FractionallySizedBox(
                            alignment: Alignment.centerLeft,
                            widthFactor:
                                (_index + 1) / _kOnboardingPages.length,
                            child: AnimatedContainer(
                              duration: const Duration(milliseconds: 250),
                              height: 2,
                              decoration: BoxDecoration(
                                color: _accent,
                                borderRadius: BorderRadius.circular(1),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 22),
                      InkWell(
                        onTap: _next,
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            Text(
                              isLast ? '시작하기' : '다음',
                              style: const TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                            Container(
                              width: 44,
                              height: 44,
                              decoration: BoxDecoration(
                                color: _accent,
                                shape: BoxShape.circle,
                              ),
                              child: const Icon(
                                Icons.arrow_forward_rounded,
                                color: Colors.white,
                                size: 20,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
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

class _DiagonalClipper extends CustomClipper<Path> {
  @override
  Path getClip(Size size) {
    final path = Path();
    path.lineTo(0, 0);
    path.lineTo(size.width, 0);
    path.lineTo(0, size.height);
    path.close();
    return path;
  }

  @override
  bool shouldReclip(CustomClipper<Path> oldClipper) => false;
}
