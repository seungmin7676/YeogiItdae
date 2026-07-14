import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/backend_exception.dart';
import '../theme/app_theme.dart';
import '../widgets/hallym_logo.dart';
import 'password_reset_screen.dart';

enum _AuthMode { login, signup }

/// 화면: 한림대 웹메일(@hallym.ac.kr) 전용 로그인/회원가입
class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen> {
  final _formKey = GlobalKey<FormState>();
  final _emailController = TextEditingController();
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _realNameController = TextEditingController();
  final _departmentController = TextEditingController();
  final _studentIdController = TextEditingController();

  _AuthMode _mode = _AuthMode.login;
  bool _isSubmitting = false;
  bool _agreedToPrivacy = false;

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    _nicknameController.dispose();
    _realNameController.dispose();
    _departmentController.dispose();
    _studentIdController.dispose();
    super.dispose();
  }

  /// 이메일 입력란에는 "@hallym.ac.kr" 앞부분(학번)만 입력받고, 도메인은
  /// 화면에 고정 표기해 항상 자동으로 붙인다.
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
    if (value == null || value.length < 8) {
      return '비밀번호는 8자 이상 입력해주세요.';
    }
    return null;
  }

  String? _validateNickname(String? value) {
    final nickname = value?.trim() ?? '';
    if (nickname.isEmpty) return '닉네임을 입력해주세요.';
    if (nickname.length > 12) return '닉네임은 12자 이하로 입력해주세요.';
    return null;
  }

  String? _validateRealName(String? value) {
    if ((value?.trim() ?? '').isEmpty) return '이름을 입력해주세요.';
    return null;
  }

  String? _validateDepartment(String? value) {
    if ((value?.trim() ?? '').isEmpty) return '학과를 입력해주세요.';
    return null;
  }

  String? _validateStudentId(String? value) {
    final studentId = value?.trim() ?? '';
    if (studentId.isEmpty) return '학번을 입력해주세요.';
    if (!RegExp(r'^\d{6,10}$').hasMatch(studentId)) {
      return '학번은 숫자 6~10자로 입력해주세요.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;

    if (_mode == _AuthMode.signup && !_agreedToPrivacy) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('개인정보 수집 및 이용에 동의해주세요.')));
      return;
    }

    setState(() => _isSubmitting = true);
    final email = _fullEmail;
    final password = _passwordController.text;

    try {
      if (_mode == _AuthMode.login) {
        await FirebaseAuth.instance.signInWithEmailAndPassword(
          email: email,
          password: password,
        );
      } else {
        final nickname = _nicknameController.text.trim();
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        final user = credential.user!;
        await user.updateDisplayName(nickname);
        await user.reload();
        await FirebaseFirestore.instance
            .collection('userPublicProfiles')
            .doc(user.uid)
            .set({'nickname': nickname});

        try {
          await FirebaseFirestore.instance
              .collection('userPrivate')
              .doc(user.uid)
              .set({
                'nickname': nickname,
                'realName': _realNameController.text.trim(),
                'department': _departmentController.text.trim(),
                'studentId': _studentIdController.text.trim(),
                'email': email,
                'createdAt': FieldValue.serverTimestamp(),
              });
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('프로필 저장 중 문제가 발생했어요. 다음 화면에서 다시 입력해주세요.'),
              ),
            );
          }
        }
      }
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(_authErrorMessage(e))));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('오류가 발생했습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  String _authErrorMessage(FirebaseAuthException e) {
    switch (e.code) {
      case 'email-already-in-use':
        return '이미 가입된 이메일입니다.';
      case 'invalid-email':
        return '이메일 형식이 올바르지 않습니다.';
      case 'weak-password':
        return '비밀번호가 너무 약합니다.';
      case 'user-not-found':
      case 'wrong-password':
      case 'invalid-credential':
        return '이메일 또는 비밀번호가 올바르지 않습니다.';
      default:
        return '오류가 발생했습니다: ${e.message}';
    }
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
    final isLogin = _mode == _AuthMode.login;
    return Scaffold(
      backgroundColor: AppColors.bg,
      body: SafeArea(
        child: Center(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: Form(
              key: _formKey,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      const HallymLogo(size: 36),
                      const SizedBox(width: 10),
                      const Text(
                        '여기있대!',
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.w700,
                          color: AppColors.inkMuted,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 36),
                  Text(
                    isLogin ? '다시 만나서\n반가워요' : '캠퍼스에서\n잃어버린 걸 찾아보세요',
                    style: const TextStyle(
                      fontSize: 28,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.6,
                      height: 1.25,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    '한림대학교 캠퍼스 분실물 찾기 · $kAllowedEmailDomain 계정으로 시작하세요',
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: AppColors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    validator: _validateEmail,
                    decoration: _inputDecoration(
                      '학교 이메일',
                      hint: '학번',
                      suffixText: kAllowedEmailDomain,
                    ),
                  ),
                  const SizedBox(height: 14),
                  TextFormField(
                    controller: _passwordController,
                    obscureText: true,
                    validator: _validatePassword,
                    decoration: _inputDecoration('비밀번호', hint: '8자 이상'),
                  ),
                  if (!isLogin) ...[
                    const SizedBox(height: 24),
                    Text(
                      '실명·학과·학번은 도난 등 문제 발생 시에만 사용되며\n다른 사용자에게 공개되지 않습니다.\n',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _nicknameController,
                      validator: _validateNickname,
                      decoration: _inputDecoration(
                        '닉네임',
                        hint: '다른 사용자에게 공개되는 이름',
                      ),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _realNameController,
                      validator: _validateRealName,
                      decoration: _inputDecoration('이름', hint: '실명'),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _departmentController,
                      validator: _validateDepartment,
                      decoration: _inputDecoration('학과', hint: ''),
                    ),
                    const SizedBox(height: 14),
                    TextFormField(
                      controller: _studentIdController,
                      keyboardType: TextInputType.number,
                      validator: _validateStudentId,
                      decoration: _inputDecoration('학번 또는 사번', hint: '숫자만 입력'),
                    ),
                    const SizedBox(height: 16),
                    InkWell(
                      onTap: () {
                        setState(() => _agreedToPrivacy = !_agreedToPrivacy);
                      },
                      borderRadius: BorderRadius.circular(14),
                      child: Container(
                        padding: const EdgeInsets.fromLTRB(12, 10, 14, 14),
                        decoration: BoxDecoration(
                          color: _agreedToPrivacy
                              ? AppColors.primary.withValues(alpha: 0.06)
                              : AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(
                            color: _agreedToPrivacy
                                ? AppColors.primary.withValues(alpha: 0.4)
                                : AppColors.line,
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            IgnorePointer(
                              // 이 체크박스는 순전히 시각적 표시용이다. 탭 처리는
                              // 바깥 InkWell 하나만 담당한다 — 체크박스가 자체
                              // onChanged로도 탭을 받으면 정확히 체크박스 위를
                              // 눌렀을 때 두 콜백이 경합해 두 번 토글되어(상쇄되어)
                              // 아무 반응도 없는 것처럼 보이는 문제가 있었다.
                              child: Checkbox(
                                value: _agreedToPrivacy,
                                activeColor: AppColors.primary,
                                visualDensity: VisualDensity.compact,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                onChanged: (_) {},
                              ),
                            ),
                            const SizedBox(width: 8),
                            const Expanded(
                              child: Padding(
                                padding: EdgeInsets.only(top: 4),
                                child: Text(
                                  '(필수) 이름·학과·학번 등 개인정보 수집 및 이용에 동의합니다.\n'
                                  '수집된 정보는 분실물 관련 분쟁(도난 등) 발생 시에만 사용되며, 다른 사용자에게 공개되지 않습니다.',
                                  style: TextStyle(
                                    fontSize: 12,
                                    height: 1.5,
                                    color: AppColors.inkMuted,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
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
                        : Text(isLogin ? '로그인' : '회원가입'),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: _isSubmitting
                        ? null
                        : () {
                            setState(() {
                              _mode = isLogin
                                  ? _AuthMode.signup
                                  : _AuthMode.login;
                            });
                          },
                    child: Text(
                      isLogin ? '계정이 없으신가요? 회원가입' : '이미 계정이 있으신가요? 로그인',
                      style: const TextStyle(
                        color: AppColors.primary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  if (isLogin)
                    TextButton(
                      onPressed: _isSubmitting ? null : _goToPasswordReset,
                      child: const Text(
                        '비밀번호를 잊으셨나요?',
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

  InputDecoration _inputDecoration(
    String label, {
    required String hint,
    String? suffixText,
  }) => appInputDecoration(label, hint: hint, suffixText: suffixText);
}
