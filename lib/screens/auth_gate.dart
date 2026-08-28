import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/onboarding_service.dart';
import '../widgets/full_screen_status.dart';
import 'complete_profile_screen.dart';
import 'email_verification_screen.dart';
import 'login_screen.dart';
import 'main_nav_screen.dart';
import 'onboarding_screen.dart';

/// 로그인 상태에 따라 로그인/이메일 인증 대기/메인 피드 화면을 전환한다.
class AuthGate extends StatefulWidget {
  const AuthGate({super.key});

  @override
  State<AuthGate> createState() => _AuthGateState();
}

class _AuthGateState extends State<AuthGate> {
  late Stream<User?> _authStream = FirebaseAuth.instance.userChanges();

  void _retry() {
    setState(() => _authStream = FirebaseAuth.instance.userChanges());
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: _authStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: FullScreenStatus(
              title: '로그인 상태를 확인하지 못했어요',
              message: '네트워크 연결을 확인한 뒤 다시 시도해주세요.',
              actionLabel: '다시 시도',
              onAction: _retry,
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: FullScreenStatus.loading(
              title: '로그인 정보를 확인하고 있어요',
              message: '잠시만 기다려주세요.',
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
class _ProfileGate extends StatefulWidget {
  final String uid;
  final String nickname;

  const _ProfileGate({required this.uid, required this.nickname});

  @override
  State<_ProfileGate> createState() => _ProfileGateState();
}

class _ProfileGateState extends State<_ProfileGate> {
  late Stream<DocumentSnapshot<Map<String, dynamic>>> _profileStream =
      _createStream();

  Stream<DocumentSnapshot<Map<String, dynamic>>> _createStream() =>
      FirebaseFirestore.instance
          .collection('userPrivate')
          .doc(widget.uid)
          .snapshots();

  void _retry() => setState(() => _profileStream = _createStream());

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
      stream: _profileStream,
      builder: (context, snapshot) {
        if (snapshot.hasError) {
          return Scaffold(
            body: FullScreenStatus(
              title: '프로필 정보를 확인하지 못했어요',
              message: '입력한 정보는 변경되지 않았어요.\n연결 상태를 확인하고 다시 시도해주세요.',
              actionLabel: '다시 시도',
              onAction: _retry,
            ),
          );
        }
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: FullScreenStatus.loading(
              title: '프로필을 준비하고 있어요',
              message: '잠시만 기다려주세요.',
            ),
          );
        }
        if (snapshot.data?.exists != true) {
          return CompleteProfileScreen(
            uid: widget.uid,
            nickname: widget.nickname,
          );
        }
        return _OnboardingGate(uid: widget.uid);
      },
    );
  }
}

/// 이 계정이 사용법 튜토리얼을 아직 보지 않았다면 먼저 보여주고,
/// 이미 봤다면 곧바로 메인 화면으로 진입한다.
///
/// 튜토리얼 완료 여부는 라우트를 새로 쌓지 않고 이 위젯 내부 상태로만
/// 전환한다. Navigator.push로 화면을 바꾸면 AuthGate의 로그인 상태
/// StreamBuilder 트리에서 완전히 떨어져 나가버려, 이후 로그아웃 등으로
/// 로그인 상태가 바뀌어도 화면이 반응하지 않는 문제가 있었다.
class _OnboardingGate extends StatefulWidget {
  final String uid;

  const _OnboardingGate({required this.uid});

  @override
  State<_OnboardingGate> createState() => _OnboardingGateState();
}

class _OnboardingGateState extends State<_OnboardingGate> {
  bool? _hasSeen;
  bool _hasError = false;

  @override
  void initState() {
    super.initState();
    _load(showLoading: false);
  }

  Future<void> _load({bool showLoading = true}) async {
    if (showLoading && mounted) {
      setState(() {
        _hasSeen = null;
        _hasError = false;
      });
    }
    try {
      final seen = await hasSeenOnboarding(widget.uid);
      if (mounted) setState(() => _hasSeen = seen);
    } catch (_) {
      if (mounted) setState(() => _hasError = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_hasError) {
      return Scaffold(
        body: FullScreenStatus(
          title: '시작 안내를 불러오지 못했어요',
          message: '네트워크 연결을 확인한 뒤 다시 시도해주세요.',
          actionLabel: '다시 시도',
          onAction: _load,
        ),
      );
    }
    final hasSeen = _hasSeen;
    if (hasSeen == null) {
      return const Scaffold(
        body: FullScreenStatus.loading(
          title: '앱을 준비하고 있어요',
          message: '잠시만 기다려주세요.',
        ),
      );
    }
    if (hasSeen) {
      return const MainNavScreen();
    }
    return OnboardingScreen(
      uid: widget.uid,
      onFinished: () => setState(() => _hasSeen = true),
    );
  }
}
