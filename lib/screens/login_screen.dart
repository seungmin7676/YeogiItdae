import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/backend_exception.dart';
import '../services/error_messages.dart';
import '../theme/app_theme.dart';
import '../widgets/hallym_logo.dart';
import 'password_reset_screen.dart';
import 'signup_screen.dart';

/// 화면: 한림대 웹메일(@hallym.ac.kr) 전용 로그인.
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();

  bool _isSubmitting = false;
  bool _obscurePassword = true;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  String get _fullEmail {
    final raw = _emailController.text.trim();
    if (raw.isEmpty) return '';
    final atIndex = raw.indexOf('@');
    final localPart = atIndex >= 0 ? raw.substring(0, atIndex) : raw;
    return '$localPart$kAllowedEmailDomain';
  }

  String? _validateEmail(String? value) {
    if ((value?.trim() ?? '').isEmpty) return '학번을 입력해주세요.';
    return null;
  }

  String? _validatePassword(String? value) {
    if (value == null || value.isEmpty) return '비밀번호를 입력해주세요.';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    setState(() => _isSubmitting = true);
    try {
      await FirebaseAuth.instance.signInWithEmailAndPassword(
        email: _fullEmail,
        password: _passwordController.text,
      );
      logLogin();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_authErrorMessage(e))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('오류가 발생했습니다: ${friendlyErrorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'invalid-email':
        return '이메일 형식이 올바르지 않습니다.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return '이메일 또는 비밀번호가 올바르지 않습니다.';
      default:
        return '오류가 발생했습니다: ${e.message}';
    }
  }

  void _goToSignup() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => SignupScreen(initialEmail: _fullEmail),
      ),
    );
  }

  void _goToPasswordReset() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => PasswordResetScreen(initialEmail: _fullEmail),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: LayoutBuilder(
          builder: (context, constraints) {
            const verticalPadding = 24.0;
            final minimumContentHeight =
                constraints.maxHeight > verticalPadding * 2
                ? constraints.maxHeight - verticalPadding * 2
                : 0.0;

            return SingleChildScrollView(
              padding: const EdgeInsets.symmetric(
                horizontal: 24,
                vertical: verticalPadding,
              ),
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              child: ConstrainedBox(
                constraints: BoxConstraints(minHeight: minimumContentHeight),
                child: Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: kFormMaxWidth),
                    child: Form(
                      key: _formKey,
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Column(
                            children: [
                              HallymLogo(size: 56),
                              SizedBox(height: 14),
                              Text(
                                '여기있대!',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.w800,
                                  letterSpacing: -0.6,
                                  color: AppColors.ink,
                                ),
                              ),
                              SizedBox(height: 6),
                              Text(
                                '캠퍼스에서 잃어버린 물건을 찾아보세요',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 14,
                                  color: AppColors.ink,
                                  fontWeight: FontWeight.w600,
                                  letterSpacing: -0.2,
                                ),
                              ),
                              SizedBox(height: 4),
                              Text(
                                '$kAllowedEmailDomain 계정으로 시작하세요',
                                textAlign: TextAlign.center,
                                style: TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.inkMuted,
                                  fontWeight: FontWeight.w500,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 32),
                          TextFormField(
                            controller: _emailController,
                            validator: _validateEmail,
                            keyboardType: TextInputType.emailAddress,
                            textInputAction: TextInputAction.next,
                            autofillHints: const [AutofillHints.username],
                            decoration: _inputDecoration(
                              '학교 이메일',
                              hint: '학번',
                              suffixText: kAllowedEmailDomain,
                            ),
                          ),
                          const SizedBox(height: 14),
                          TextFormField(
                            controller: _passwordController,
                            obscureText: _obscurePassword,
                            validator: _validatePassword,
                            textInputAction: TextInputAction.done,
                            autofillHints: const [AutofillHints.password],
                            onFieldSubmitted: (_) {
                              if (!_isSubmitting) _submit();
                            },
                            decoration: _inputDecoration(
                              '비밀번호',
                              hint: '비밀번호',
                              suffixIcon: IconButton(
                                icon: Icon(
                                  _obscurePassword
                                      ? Icons.visibility_off_outlined
                                      : Icons.visibility_outlined,
                                  color: AppColors.inkMuted,
                                  size: 20,
                                ),
                                tooltip: _obscurePassword
                                    ? '비밀번호 표시'
                                    : '비밀번호 숨기기',
                                onPressed: () => setState(
                                  () => _obscurePassword = !_obscurePassword,
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: _isSubmitting ? null : _submit,
                            child: _isSubmitting
                                ? const SizedBox(
                                    width: 22,
                                    height: 22,
                                    child: CircularProgressIndicator(
                                      color: Colors.white,
                                      strokeWidth: 2.5,
                                    ),
                                  )
                                : const Text('로그인'),
                          ),
                          const SizedBox(height: 8),
                          TextButton(
                            onPressed: _isSubmitting ? null : _goToSignup,
                            child: const Text(
                              '계정이 없으신가요? 회원가입',
                              style: TextStyle(
                                color: AppColors.primary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                          const Padding(
                            padding: EdgeInsets.symmetric(
                              vertical: 6,
                              horizontal: 8,
                            ),
                            child: Row(
                              children: [
                                Expanded(
                                  child: Divider(
                                    color: AppColors.line,
                                    height: 1,
                                  ),
                                ),
                                Padding(
                                  padding: EdgeInsets.symmetric(horizontal: 12),
                                  child: Text(
                                    '또는',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      color: AppColors.inkFaint,
                                      fontWeight: FontWeight.w500,
                                    ),
                                  ),
                                ),
                                Expanded(
                                  child: Divider(
                                    color: AppColors.line,
                                    height: 1,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          TextButton(
                            onPressed: _isSubmitting
                                ? null
                                : _goToPasswordReset,
                            child: const Text(
                              '비밀번호를 잊으셨나요?',
                              style: TextStyle(
                                color: AppColors.inkMuted,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  InputDecoration _inputDecoration(
    String label, {
    required String hint,
    String? suffixText,
    Widget? suffixIcon,
  }) => appInputDecoration(
    label,
    hint: hint,
    suffixText: suffixText,
    suffixIcon: suffixIcon,
    fillColor: AppColors.surfaceAlt,
  );
}
