import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/analytics_service.dart';
import '../services/backend_exception.dart';
import '../services/error_messages.dart';
import '../services/withdrawal.dart';
import '../theme/app_theme.dart';
import '../widgets/department_field.dart';
import 'privacy_policy_screen.dart';

/// 화면: 한림대 웹메일 계정 회원가입.
class SignupScreen extends StatefulWidget {
  final String initialEmail;

  const SignupScreen({super.key, this.initialEmail = ''});

  @override
  State<SignupScreen> createState() => _SignupScreenState();
}

class _SignupScreenState extends State<SignupScreen> {
  final _formKey = GlobalKey<FormState>();
  late final TextEditingController _emailController;
  final _passwordController = TextEditingController();
  final _nicknameController = TextEditingController();
  final _realNameController = TextEditingController();
  final _departmentController = TextEditingController();
  final _studentIdController = TextEditingController();

  bool _isSubmitting = false;
  bool _agreedToPrivacy = false;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    final initialEmail = widget.initialEmail.trim();
    final atIndex = initialEmail.indexOf('@');
    _emailController = TextEditingController(
      text: atIndex >= 0 ? initialEmail.substring(0, atIndex) : initialEmail,
    );
  }

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
    final emailLocalPart = _fullEmail.split('@').first;
    if (emailLocalPart.isNotEmpty && studentId != emailLocalPart) {
      return '위 이메일 아이디와 같은 학번·사번을 입력해주세요.';
    }
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    if (!_agreedToPrivacy) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('개인정보 수집 및 이용에 동의해주세요.')));
      return;
    }

    setState(() => _isSubmitting = true);
    final email = _fullEmail;
    final password = _passwordController.text;

    try {
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
      } catch (_) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('프로필 저장 중 문제가 발생했어요. 다음 화면에서 다시 입력해주세요.'),
            ),
          );
        }
      }

      if (mounted) Navigator.pop(context);
    } on WithdrawnCooldownException catch (e) {
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
      default:
        return '오류가 발생했습니다: ${e.message}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('회원가입'),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
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
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    const Text(
                      '한림대학교 계정으로 가입하기',
                      style: TextStyle(
                        fontSize: 22,
                        fontWeight: FontWeight.w800,
                        color: AppColors.ink,
                        letterSpacing: -0.4,
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      '학교 이메일과 기본 정보를 입력해주세요.',
                      style: TextStyle(
                        fontSize: 14,
                        color: AppColors.inkMuted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 24),
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
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.newPassword],
                      decoration: _inputDecoration(
                        '비밀번호',
                        hint: '8자 이상',
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
                    const SizedBox(height: 24),
                    const Text(
                      '실명·학과·학번은 도난 등 문제 발생 시에만 사용되며\n'
                      '다른 사용자에게 공개되지 않습니다.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        fontSize: 12,
                        color: AppColors.inkMuted,
                        height: 1.5,
                      ),
                    ),
                    const SizedBox(height: 18),
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
                      decoration: _inputDecoration('학번 또는 사번', hint: '숫자만 입력'),
                    ),
                    const SizedBox(height: 16),
                    Semantics(
                      checked: _agreedToPrivacy,
                      label: '개인정보 수집 및 이용 동의(필수)',
                      child: InkWell(
                        onTap: () => setState(
                          () => _agreedToPrivacy = !_agreedToPrivacy,
                        ),
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
                    const SizedBox(height: 16),
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
                          : const Text('회원가입'),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: _isSubmitting
                          ? null
                          : () => Navigator.pop(context),
                      child: const Text('이미 계정이 있으신가요? 로그인'),
                    ),
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
