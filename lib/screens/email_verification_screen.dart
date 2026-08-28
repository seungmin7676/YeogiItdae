import 'dart:async';
import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/backend_exception.dart';
import '../services/backend_http.dart';
import '../theme/app_theme.dart';

const int _kResendCooldownSeconds = 60;

/// 화면: 이메일 인증 코드 입력
class EmailVerificationScreen extends StatefulWidget {
  const EmailVerificationScreen({super.key});

  @override
  State<EmailVerificationScreen> createState() =>
      _EmailVerificationScreenState();
}

class _EmailVerificationScreenState extends State<EmailVerificationScreen> {
  final _codeController = TextEditingController();

  bool _isVerifying = false;
  bool _isSending = false;
  String? _errorText;
  Timer? _cooldownTimer;
  int _cooldownSeconds = 0;

  @override
  void initState() {
    super.initState();
    _sendCode(silent: true);
  }

  @override
  void dispose() {
    _codeController.dispose();
    _cooldownTimer?.cancel();
    super.dispose();
  }

  void _startCooldown() {
    _cooldownTimer?.cancel();
    setState(() => _cooldownSeconds = _kResendCooldownSeconds);
    _cooldownTimer = Timer.periodic(const Duration(seconds: 1), (timer) {
      if (!mounted) {
        timer.cancel();
        return;
      }
      if (_cooldownSeconds <= 1) {
        timer.cancel();
        setState(() => _cooldownSeconds = 0);
      } else {
        setState(() => _cooldownSeconds -= 1);
      }
    });
  }

  Future<Map<String, dynamic>> _callBackend(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final response = await postBackend(
      Uri.parse('$kVerifyBackendUrl$path'),
      headers: await backendSecurityHeaders(authenticate: true),
      body: jsonEncode(body ?? {}),
    );
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw BackendException(
        decoded['error'] as String? ?? 'unknown',
        data: decoded,
      );
    }
    return decoded;
  }

  String _sendErrorMessage(String code) {
    switch (code) {
      case 'domain-not-allowed':
        return '한림대학교 웹메일 계정만 인증할 수 있습니다.';
      case 'cooldown':
        return '방금 코드를 보냈어요. 잠시 후 다시 시도해주세요.';
      default:
        return '코드 발송에 실패했습니다. 잠시 후 다시 시도해주세요.';
    }
  }

  /// 탈퇴 후 재가입 제한에 걸린 경우. 백엔드가 방금 만들어진 계정을 이미
  /// 되돌렸으므로, 이 기기의 로그인 상태만 정리하고 이유를 알려준다.
  Future<void> _handleWithdrawnCooldown(int daysLeft) async {
    await FirebaseAuth.instance.signOut();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('지금은 가입할 수 없어요'),
        content: Text(
          '탈퇴한 계정과 같은 학번으로는 바로 다시 가입할 수 없어요.\n$daysLeft일 뒤부터 가입할 수 있습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: const Text('확인'),
          ),
        ],
      ),
    );
  }

  String _verifyErrorMessage(String code) {
    switch (code) {
      case 'no-code':
        return '발송된 코드가 없습니다. 코드를 다시 요청해주세요.';
      case 'expired':
        return '코드가 만료되었습니다. 코드를 다시 요청해주세요.';
      case 'too-many-attempts':
        return '시도 횟수를 초과했습니다. 코드를 다시 요청해주세요.';
      case 'wrong-code':
        return '인증 코드가 올바르지 않습니다.';
      default:
        return '인증에 실패했습니다. 잠시 후 다시 시도해주세요.';
    }
  }

  Future<void> _sendCode({bool silent = false}) async {
    setState(() => _isSending = true);
    try {
      await _callBackend('/api/send-code');
      _startCooldown();
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('인증 코드를 보냈습니다. 메일함을 확인해주세요.')),
        );
      }
    } on BackendException catch (e) {
      // 재가입 제한은 화면에 처음 들어오자마자(silent) 걸리는 경우가 대부분이라,
      // 다른 오류와 달리 조용히 넘기면 안 된다 — 백엔드가 계정을 되돌린 상태라
      // 그대로 두면 사용자가 아무것도 못 하는 인증 화면에 갇힌다.
      if (e.code == 'withdrawn-cooldown') {
        await _handleWithdrawnCooldown(e.intValue('daysLeft') ?? 0);
        return;
      }
      if (e.code == 'cooldown') _startCooldown();
      if (mounted && !silent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_sendErrorMessage(e.code))));
      }
    } on BackendRequestTimeoutException {
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('서버 응답이 늦어 요청을 중단했어요. 다시 시도해주세요.')),
        );
      }
    } catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('코드 발송 중 오류가 발생했습니다.')));
      }
    } finally {
      if (mounted) setState(() => _isSending = false);
    }
  }

  Future<void> _verifyCode() async {
    final code = _codeController.text.trim();
    if (code.length != 6) {
      setState(() => _errorText = '6자리 코드를 입력해주세요.');
      return;
    }

    setState(() {
      _isVerifying = true;
      _errorText = null;
    });

    try {
      await _callBackend('/api/verify-code', body: {'code': code});
      await FirebaseAuth.instance.currentUser?.reload();
      await FirebaseAuth.instance.currentUser?.getIdToken(true);
    } on BackendException catch (e) {
      // 인증에 성공하면 AuthGate가 이 화면을 곧바로 걷어내므로, 응답이
      // 늦게 온 경우 위젯이 이미 사라져 있을 수 있다. mounted를 확인하지
      // 않으면 dispose 이후 setState로 예외가 난다.
      if (mounted) setState(() => _errorText = _verifyErrorMessage(e.code));
    } on BackendRequestTimeoutException {
      if (mounted) {
        setState(() => _errorText = '서버 응답이 늦어 요청을 중단했어요. 다시 시도해주세요.');
      }
    } catch (e) {
      if (mounted) {
        setState(() => _errorText = '인증에 실패했습니다. 잠시 후 다시 시도해주세요.');
      }
    } finally {
      if (mounted) setState(() => _isVerifying = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final email = FirebaseAuth.instance.currentUser?.email ?? '';
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: kFormMaxWidth),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 64,
                    height: 64,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: AppColors.primaryMuted,
                      borderRadius: BorderRadius.circular(kRadiusLg),
                    ),
                    child: const Icon(
                      Icons.mark_email_unread_outlined,
                      color: AppColors.primary,
                      size: 32,
                    ),
                  ),
                  const SizedBox(height: 20),
                  const Text(
                    '이메일 인증 코드를 입력해주세요',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.w800),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '$email 로 전송된 6자리 코드를 입력해주세요.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13,
                      color: AppColors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 28),
                  TextField(
                    controller: _codeController,
                    keyboardType: TextInputType.number,
                    textAlign: TextAlign.center,
                    maxLength: 6,
                    style: const TextStyle(
                      fontSize: 24,
                      fontWeight: FontWeight.w700,
                      letterSpacing: 8,
                    ),
                    decoration: InputDecoration(
                      counterText: '',
                      hintText: '------',
                      errorText: _errorText,
                      filled: true,
                      fillColor: AppColors.surfaceAlt,
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(kRadiusMd),
                        borderSide: BorderSide.none,
                      ),
                      enabledBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(kRadiusMd),
                        borderSide: BorderSide.none,
                      ),
                      focusedBorder: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(kRadiusMd),
                        borderSide: const BorderSide(
                          color: AppColors.primary,
                          width: 1.6,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 20),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _isVerifying ? null : _verifyCode,
                      child: _isVerifying
                          ? const SizedBox(
                              width: 22,
                              height: 22,
                              child: CircularProgressIndicator(
                                color: Colors.white,
                                strokeWidth: 2.5,
                              ),
                            )
                          : const Text('인증 확인'),
                    ),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: (_isSending || _cooldownSeconds > 0)
                        ? null
                        : () => _sendCode(),
                    child: Text(
                      _isSending
                          ? '전송 중...'
                          : _cooldownSeconds > 0
                          ? '$_cooldownSeconds초 후 재전송 가능'
                          : '코드 재전송',
                    ),
                  ),
                  TextButton(
                    onPressed: () => FirebaseAuth.instance.signOut(),
                    child: const Text(
                      '로그아웃',
                      style: TextStyle(color: AppColors.inkMuted),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
