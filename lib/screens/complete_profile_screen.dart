import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';

import '../services/error_messages.dart';
import '../theme/app_theme.dart';
import '../widgets/department_field.dart';

/// 화면: 회원가입 중 실패해 비어있던 프로필(실명/학과/학번)을 다시 입력받는다.
class CompleteProfileScreen extends StatefulWidget {
  final String uid;
  final String nickname;

  const CompleteProfileScreen({
    super.key,
    required this.uid,
    required this.nickname,
  });

  @override
  State<CompleteProfileScreen> createState() => _CompleteProfileScreenState();
}

class _CompleteProfileScreenState extends State<CompleteProfileScreen> {
  final _formKey = GlobalKey<FormState>();
  final _realNameController = TextEditingController();
  final _departmentController = TextEditingController();
  final _studentIdController = TextEditingController();
  bool _isSubmitting = false;

  @override
  void dispose() {
    _realNameController.dispose();
    _departmentController.dispose();
    _studentIdController.dispose();
    super.dispose();
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
    if ((value?.trim() ?? '').isEmpty) return '학번을 입력해주세요.';
    return null;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    setState(() => _isSubmitting = true);
    try {
      await FirebaseFirestore.instance
          .collection('userPrivate')
          .doc(widget.uid)
          .set({
            'nickname': widget.nickname,
            'realName': _realNameController.text.trim(),
            'department': _departmentController.text.trim(),
            'studentId': _studentIdController.text.trim(),
            'email': FirebaseAuth.instance.currentUser?.email ?? '',
            'createdAt': FieldValue.serverTimestamp(),
          });
      // 저장이 끝나면 _ProfileGate의 StreamBuilder가 자동으로 감지해
      // MainNavScreen으로 전환하므로 별도 네비게이션이 필요 없다.
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('저장하지 못했습니다: ${friendlyErrorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSubmitting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('프로필 완성하기'),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(24),
          child: Form(
            key: _formKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                const Text(
                  '가입 중 프로필 저장이 완료되지 않았어요.\n'
                  '실명 공개 등 신원 확인 기능을 사용하려면\n'
                  '아래 정보를 다시 입력해주세요.',
                  style: TextStyle(color: AppColors.inkMuted, height: 1.5),
                ),
                const SizedBox(height: 20),
                TextFormField(
                  controller: _realNameController,
                  validator: _validateRealName,
                  decoration: appInputDecoration('이름', hint: '실명'),
                ),
                const SizedBox(height: 14),
                DepartmentField(
                  controller: _departmentController,
                  validator: _validateDepartment,
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _studentIdController,
                  keyboardType: TextInputType.number,
                  validator: _validateStudentId,
                  decoration: appInputDecoration('학번 또는 사번', hint: '숫자만 입력'),
                ),
                const SizedBox(height: 20),
                ElevatedButton(
                  onPressed: _isSubmitting ? null : _submit,
                  child: _isSubmitting
                      ? const SizedBox(
                          width: 22,
                          height: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2,
                            color: Colors.white,
                          ),
                        )
                      : const Text('저장하고 시작하기'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
