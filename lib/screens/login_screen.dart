import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/backend_exception.dart';
import '../services/error_messages.dart';
import '../services/withdrawal.dart';
import '../theme/app_theme.dart';
import '../widgets/department_field.dart';
import '../widgets/hallym_logo.dart';
import 'password_reset_screen.dart';
import 'privacy_policy_screen.dart';

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
  bool _obscurePassword = true;

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
    if (value == null || value.isEmpty) return '비밀번호를 입력해주세요.';
    // 새 계정은 8자 이상으로 받되, 로그인은 Firebase의 기존 최소 길이(6자)로
    // 만들어진 전시 관리자·기존 계정도 사용할 수 있어야 한다.
    if (_mode == _AuthMode.signup && value.length < 8) {
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
    // 학번뿐 아니라 교직원 사번도 함께 입력받는 필드라 자릿수가 1~10자로
    // 다양하다. 형식은 따로 검증하지 않고 입력 여부만 확인한다.
    final studentId = value?.trim() ?? '';
    if (studentId.isEmpty) return '학번을 입력해주세요.';
    final emailLocalPart = _fullEmail.split('@').first;
    if (emailLocalPart.isNotEmpty && studentId != emailLocalPart) {
      return '위 이메일 아이디와 같은 학번·사번을 입력해주세요.';
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
        logLogin();
      } else {
        // 탈퇴 후 재가입 제한에 걸리는지 계정을 만들기 전에 확인한다.
        // (실제 차단은 백엔드의 이메일 인증 관문이 한다 — withdrawal.dart 참고)
        await ensureSignupAllowed(email);

        final nickname = _nicknameController.text.trim();
        final credential = await FirebaseAuth.instance
            .createUserWithEmailAndPassword(email: email, password: password);
        final user = credential.user!;
        await user.updateDisplayName(nickname);
        await user.reload();
        logSignUp();
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
    } on WithdrawnCooldownException catch (e) {
      // 스낵바로는 놓치기 쉬운 안내라(가입이 아예 막히는 상황) 다이얼로그로 알린다.
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('지금은 가입할 수 없어요'),
            content: Text(e.message),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext),
                child: const Text('확인'),
              ),
            ],
          ),
        );
      }
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
      backgroundColor: AppColors.surface,
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kFormMaxWidth),
              child: Form(
                key: _formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Column(
                      children: [
                        const HallymLogo(size: 56),
                        const SizedBox(height: 14),
                        const Text(
                          '여기있대!',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 26,
                            fontWeight: FontWeight.w800,
                            letterSpacing: -0.6,
                            color: AppColors.ink,
                          ),
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '캠퍼스에서 잃어버린 물건을 찾아보세요',
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            fontSize: 14,
                            color: AppColors.ink,
                            fontWeight: FontWeight.w600,
                            letterSpacing: -0.2,
                          ),
                        ),
                        const SizedBox(height: 4),
                        Text(
                          '$kAllowedEmailDomain 계정으로 시작하세요',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
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
                      // 이메일 앞부분(학번)만 입력받는 칸이라 숫자 키패드가
                      // 자연스럽고, 다음 칸(비밀번호)으로 바로 넘어갈 수 있게 한다.
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
                      textInputAction: isLogin
                          ? TextInputAction.done
                          : TextInputAction.next,
                      autofillHints: [
                        isLogin
                            ? AutofillHints.password
                            : AutofillHints.newPassword,
                      ],
                      // 로그인 화면에서는 마지막 칸이므로 키보드의 완료로 바로
                      // 로그인까지 이어지게 한다.
                      onFieldSubmitted: (_) {
                        if (isLogin && !_isSubmitting) _submit();
                      },
                      decoration: _inputDecoration(
                        '비밀번호',
                        hint: '8자 이상',
                        // 오타 때문에 로그인이 막히는 일이 잦은 자리라, 직접
                        // 확인할 수 있는 표시/숨김 전환을 둔다.
                        suffixIcon: IconButton(
                          icon: Icon(
                            _obscurePassword
                                ? Icons.visibility_off_outlined
                                : Icons.visibility_outlined,
                            color: AppColors.inkMuted,
                            size: 20,
                          ),
                          tooltip: _obscurePassword ? '비밀번호 표시' : '비밀번호 숨기기',
                          onPressed: () => setState(
                            () => _obscurePassword = !_obscurePassword,
                          ),
                        ),
                      ),
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
                        maxLength: 12,
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
                      DepartmentField(
                        controller: _departmentController,
                        validator: _validateDepartment,
                        fillColor: AppColors.surfaceAlt,
                      ),
                      const SizedBox(height: 14),
                      TextFormField(
                        controller: _studentIdController,
                        keyboardType: TextInputType.number,
                        validator: _validateStudentId,
                        decoration: _inputDecoration(
                          '학번 또는 사번',
                          hint: '숫자만 입력',
                        ),
                      ),
                      const SizedBox(height: 16),
                      // 탭 처리를 바깥 InkWell 하나가 맡고 Checkbox는 표시용이라,
                      // 스크린 리더에는 이 영역 전체를 하나의 체크박스로 알린다.
                      Semantics(
                        checked: _agreedToPrivacy,
                        label: '개인정보 수집 및 이용 동의(필수)',
                        child: InkWell(
                          onTap: () {
                            setState(
                              () => _agreedToPrivacy = !_agreedToPrivacy,
                            );
                          },
                          borderRadius: BorderRadius.circular(kRadiusMd),
                          child: Container(
                            padding: const EdgeInsets.fromLTRB(12, 10, 14, 14),
                            decoration: BoxDecoration(
                              color: _agreedToPrivacy
                                  ? AppColors.primaryMuted
                                  : AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(kRadiusMd),
                              border: Border.all(
                                color: _agreedToPrivacy
                                    ? AppColors.primary.withValues(alpha: 0.4)
                                    : AppColors.line,
                              ),
                            ),
                            child: Row(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                ExcludeSemantics(
                                  child: IgnorePointer(
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
                      ),
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          onPressed: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => const PrivacyPolicyScreen(),
                            ),
                          ),
                          child: const Text('개인정보 처리방침 전문 보기'),
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
                    const SizedBox(height: 8),
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
                    if (isLogin) ...[
                      const Padding(
                        padding: EdgeInsets.symmetric(
                          vertical: 6,
                          horizontal: 8,
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: Divider(color: AppColors.line, height: 1),
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
                              child: Divider(color: AppColors.line, height: 1),
                            ),
                          ],
                        ),
                      ),
                      TextButton(
                        onPressed: _isSubmitting ? null : _goToPasswordReset,
                        child: const Text(
                          '비밀번호를 잊으셨나요?',
                          style: TextStyle(
                            color: AppColors.inkMuted,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
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
    Widget? suffixIcon,
  }) => appInputDecoration(
    label,
    hint: hint,
    suffixText: suffixText,
    suffixIcon: suffixIcon,
    fillColor: AppColors.surfaceAlt,
  );
}
