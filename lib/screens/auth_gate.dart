import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/onboarding_service.dart';
import '../theme/app_theme.dart';
import 'complete_profile_screen.dart';
import 'email_verification_screen.dart';
import 'login_screen.dart';
import 'main_nav_screen.dart';
import 'onboarding_screen.dart';

/// 로그인 상태에 따라 로그인/이메일 인증 대기/메인 피드 화면을 전환한다.
class AuthGate extends StatelessWidget {
  const AuthGate({super.key});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.userChanges(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }

        final user = snapshot.data;
        if (user == null) {
          return const LoginScreen();
        }
        if (!user.emailVerified) {
          return const EmailVerificationScreen();
        }
        return _ProfileGate(uid: user.uid, nickname: user.displayName ?? '');
      },
    );
  }
}

/// 회원가입 중 네트워크 오류 등으로 userPrivate 문서 생성이 실패하면
/// 실명 공개 등 신원 관련 기능이 영구히 깨질 수 있으므로, 로그인 때마다
/// 문서 존재 여부를 확인하고 없으면 프로필을 다시 입력받는다.
class _ProfileGate extends StatelessWidget {
  final String uid;
  final String nickname;

  const _ProfileGate({required this.uid, required this.nickname});

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('userPrivate')
          .doc(uid)
          .snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        if (snapshot.data?.exists != true) {
          return CompleteProfileScreen(uid: uid, nickname: nickname);
        }
        return const _OnboardingGate();
      },
    );
  }
}

/// 이 기기에서 사용법 튜토리얼을 아직 보지 않았다면 먼저 보여주고,
/// 이미 봤다면 곧바로 메인 화면으로 진입한다.
class _OnboardingGate extends StatelessWidget {
  const _OnboardingGate();

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<bool>(
      future: hasSeenOnboarding(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            body: Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            ),
          );
        }
        return snapshot.data!
            ? const MainNavScreen()
            : const OnboardingScreen();
      },
    );
  }
}
