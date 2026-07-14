import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/backend_exception.dart';
import '../theme/app_theme.dart';

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

  @override
  void initState() {
    super.initState();
    _sendCode(silent: true);
  }

  @override
  void dispose() {
    _codeController.dispose();
    super.dispose();
  }

  Future<Map<String, dynamic>> _callBackend(
    String path, {
    Map<String, dynamic>? body,
  }) async {
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
    final response = await http.post(
      Uri.parse('$kVerifyBackendUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'Authorization': 'Bearer $idToken',
      },
      body: jsonEncode(body ?? {}),
    );
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw BackendException(decoded['error'] as String? ?? 'unknown');
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
      if (mounted && !silent) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('인증 코드를 보냈습니다. 메일함을 확인해주세요.')),
        );
      }
    } on BackendException catch (e) {
      if (mounted && !silent) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_sendErrorMessage(e.code))));
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
      setState(() => _errorText = _verifyErrorMessage(e.code));
    } catch (e) {
      setState(() => _errorText = '인증에 실패했습니다. 잠시 후 다시 시도해주세요.');
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
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 64,
                  height: 64,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(
                    color: AppColors.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(16),
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
                    fillColor: AppColors.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
                      borderSide: BorderSide(color: AppColors.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(14),
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
                  onPressed: _isSending ? null : () => _sendCode(),
                  child: Text(_isSending ? '전송 중...' : '코드 재전송'),
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
    );
  }
}
