import 'dart:convert';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../services/backend_exception.dart';
import '../theme/app_theme.dart';

/// 화면: 비밀번호 재설정 (이메일 인증과 동일한 6자리 코드 방식).
/// Firebase 기본 재설정 메일은 학교 웹메일에서 링크 접속이 불편해
/// 회원가입 때와 같은 코드 입력 방식으로 통일한다.
enum _ResetStep { email, code, newPassword }

class PasswordResetScreen extends StatefulWidget {
  final String initialEmail;

  const PasswordResetScreen({super.key, this.initialEmail = ''});

  @override
  State<PasswordResetScreen> createState() => _PasswordResetScreenState();
}

class _PasswordResetScreenState extends State<PasswordResetScreen> {
  final _emailFormKey = GlobalKey<FormState>();
  final _passwordFormKey = GlobalKey<FormState>();
  late final _emailController = TextEditingController(
    text: widget.initialEmail,
  );
  final _codeController = TextEditingController();
  final _newPasswordController = TextEditingController();
  final _confirmPasswordController = TextEditingController();

  _ResetStep _step = _ResetStep.email;
  String? _resetToken;
  bool _isSending = false;
  bool _isVerifyingCode = false;
  bool _isSubmitting = false;
  String? _codeErrorText;

  @override
  void dispose() {
    _emailController.dispose();
    _codeController.dispose();
    _newPasswordController.dispose();
    _confirmPasswordController.dispose();
    super.dispose();
  }

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return '이메일을 입력해주세요.';
    if (!email.toLowerCase().endsWith(kAllowedEmailDomain)) {
      return '한림대학교 웹메일($kAllowedEmailDomain)만 사용할 수 있습니다.';
    }
    return null;
  }

  String? _validateNewPassword(String? value) {
    if (value == null || value.length < 8) {
      return '비밀번호는 8자 이상 입력해주세요.';
    }
    return null;
  }

  String? _validateConfirmPassword(String? value) {
    if (value != _newPasswordController.text) return '비밀번호가 일치하지 않습니다.';
    return null;
  }

  Future<Map<String, dynamic>> _callBackend(
    String path,
    Map<String, dynamic> body,
  ) async {
    // 로그인 전이라 Firebase ID 토큰이 없는 화면이라, 학번 패턴을 순회하며
    // 임의 주소로 재설정 메일을 대량 발송시키는 남용을 막을 다른 수단이
    // 필요하다. App Check 토큰을 실어 보내면 서버가 "진짜 이 앱에서 온
    // 요청인지"를 확인할 수 있다. 토큰 발급 실패(콘솔에서 아직 활성화
    // 안 함 등)는 조용히 무시한다 — 서버도 검증 실패를 당장 차단하지
    // 않도록 되어 있다.
    String? appCheckToken;
    try {
      appCheckToken = (await FirebaseAppCheck.instance.getToken())?.toString();
    } catch (_) {}

    final response = await http.post(
      Uri.parse('$kVerifyBackendUrl$path'),
      headers: {
        'Content-Type': 'application/json',
        'X-Firebase-AppCheck': ?appCheckToken,
      },
      body: jsonEncode(body),
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
        return '한림대학교 웹메일 계정만 사용할 수 있습니다.';
      case 'user-not-found':
        return '가입되지 않은 이메일입니다.';
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
      case 'user-not-found':
        return '가입되지 않은 이메일입니다.';
      default:
        return '인증에 실패했습니다. 잠시 후 다시 시도해주세요.';
    }
  }

  String _resetErrorMessage(String code) {
    switch (code) {
      case 'no-token':
      case 'invalid-token':
        return '인증이 만료되었습니다. 처음부터 다시 시도해주세요.';
      case 'expired':
        return '인증이 만료되었습니다. 처음부터 다시 시도해주세요.';
      case 'user-not-found':
        return '가입되지 않은 이메일입니다.';
      default:
        return '재설정에 실패했습니다. 잠시 후 다시 시도해주세요.';
    }
  }

  Future<void> _sendCode() async {
    // 이메일 입력 단계에서만 폼 검증을 하고, 코드 단계의 "코드 재전송"은
    // 이미 검증된 이메일로 재요청하는 것이므로 검증을 건너뛴다
    // (그 단계에서는 _emailFormKey의 Form이 화면에 없어 currentState가 null이다).
    if (_step == _ResetStep.email && !_emailFormKey.currentState!.validate()) {
      return;
    }
    setState(() => _isSending = true);
    try {
      await _callBackend('/api/send-reset-code', {
        'email': _emailController.text.trim(),
      });
      if (mounted) {
        setState(() => _step = _ResetStep.code);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('인증 코드를 보냈습니다. 메일함을 확인해주세요.')),
        );
      }
    } on BackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_sendErrorMessage(e.code))));
      }
    } catch (e) {
      if (mounted) {
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
      setState(() => _codeErrorText = '6자리 코드를 입력해주세요.');
      return;
    }

    setState(() {
      _isVerifyingCode = true;
      _codeErrorText = null;
    });
    try {
      final result = await _callBackend('/api/verify-reset-code', {
        'email': _emailController.text.trim(),
        'code': code,
      });
      if (mounted) {
        setState(() {
          _resetToken = result['resetToken'] as String?;
          _step = _ResetStep.newPassword;
        });
      }
    } on BackendException catch (e) {
      setState(() => _codeErrorText = _verifyErrorMessage(e.code));
    } catch (e) {
      setState(() => _codeErrorText = '인증에 실패했습니다. 잠시 후 다시 시도해주세요.');
    } finally {
      if (mounted) setState(() => _isVerifyingCode = false);
    }
  }

  Future<void> _submitReset() async {
    if (!_passwordFormKey.currentState!.validate()) return;
    final resetToken = _resetToken;
    if (resetToken == null) {
      setState(() => _step = _ResetStep.code);
      return;
    }

    setState(() => _isSubmitting = true);
    try {
      await _callBackend('/api/reset-password', {
        'email': _emailController.text.trim(),
        'resetToken': resetToken,
        'newPassword': _newPasswordController.text,
      });
      if (mounted) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('비밀번호가 변경되었습니다. 새 비밀번호로 로그인해주세요.')),
        );
      }
    } on BackendException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_resetErrorMessage(e.code))));
        // 토큰이 만료/무효화된 경우 이 화면에 머물러봐야 계속 실패하므로
        // 처음부터 다시 시도하도록 이메일 입력 단계로 되돌린다.
        if (e.code == 'no-token' ||
            e.code == 'invalid-token' ||
            e.code == 'expired') {
          setState(() {
            _step = _ResetStep.email;
            _resetToken = null;
            _codeController.clear();
          });
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('재설정에 실패했습니다. 잠시 후 다시 시도해주세요.')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Widget body;
    switch (_step) {
      case _ResetStep.email:
        body = _buildEmailStep();
      case _ResetStep.code:
        body = _buildCodeStep();
      case _ResetStep.newPassword:
        body = _buildNewPasswordStep();
    }
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('비밀번호 재설정'),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: body,
        ),
      ),
    );
  }

  Widget _buildEmailStep() {
    return Form(
      key: _emailFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '가입한 학교 이메일로 인증 코드를 보내드릴게요.',
            style: TextStyle(color: AppColors.inkMuted, height: 1.5),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _emailController,
            keyboardType: TextInputType.emailAddress,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            validator: _validateEmail,
            decoration: appInputDecoration('학교 이메일', hint: '학번@hallym.ac.kr'),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isSending ? null : _sendCode,
            child: _isSending
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('인증 코드 보내기'),
          ),
        ],
      ),
    );
  }

  Widget _buildCodeStep() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          '${_emailController.text.trim()} 로 전송된\n6자리 코드를 입력해주세요.',
          style: const TextStyle(color: AppColors.inkMuted, height: 1.5),
        ),
        const SizedBox(height: 20),
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
            errorText: _codeErrorText,
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
        ElevatedButton(
          onPressed: _isVerifyingCode ? null : _verifyCode,
          child: _isVerifyingCode
              ? const SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('인증 확인'),
        ),
        const SizedBox(height: 12),
        TextButton(
          onPressed: _isSending ? null : _sendCode,
          child: Text(_isSending ? '전송 중...' : '코드 재전송'),
        ),
      ],
    );
  }

  Widget _buildNewPasswordStep() {
    return Form(
      key: _passwordFormKey,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text(
            '인증이 완료됐어요. 새로 사용할 비밀번호를 입력해주세요.',
            style: TextStyle(color: AppColors.inkMuted, height: 1.5),
          ),
          const SizedBox(height: 20),
          TextFormField(
            controller: _newPasswordController,
            obscureText: true,
            validator: _validateNewPassword,
            decoration: appInputDecoration('새 비밀번호', hint: '8자 이상'),
          ),
          const SizedBox(height: 14),
          TextFormField(
            controller: _confirmPasswordController,
            obscureText: true,
            validator: _validateConfirmPassword,
            decoration: appInputDecoration('새 비밀번호 확인', hint: ''),
          ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: _isSubmitting ? null : _submitReset,
            child: _isSubmitting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: Colors.white,
                    ),
                  )
                : const Text('비밀번호 변경하기'),
          ),
        ],
      ),
    );
  }
}
