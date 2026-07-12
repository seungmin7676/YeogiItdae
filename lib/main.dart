import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'firebase_options.dart';

/// 로그인 허용 이메일 도메인 (한림대학교 웹메일)
const String kAllowedEmailDomain = '@hallym.ac.kr';

/// Cloudinary 무료 티어 이미지 업로드 설정.
const String kCloudinaryCloudName = 'g2k5cwry';
const String kCloudinaryUploadPreset = 'YeogiItdae';

/// 선택한 이미지를 Cloudinary에 업로드하고 접근 가능한 URL을 반환한다.
Future<String> uploadImageToCloudinary(XFile file) async {
  final bytes = await file.readAsBytes();
  final uri = Uri.parse(
    'https://api.cloudinary.com/v1_1/$kCloudinaryCloudName/image/upload',
  );

  final request = http.MultipartRequest('POST', uri)
    ..fields['upload_preset'] = kCloudinaryUploadPreset
    ..files.add(
      http.MultipartFile.fromBytes('file', bytes, filename: file.name),
    );

  final streamedResponse = await request.send();
  final response = await http.Response.fromStream(streamedResponse);

  if (response.statusCode >= 400) {
    throw Exception('이미지 업로드에 실패했습니다 (${response.statusCode})');
  }

  final decoded = jsonDecode(response.body) as Map<String, dynamic>;
  return decoded['secure_url'] as String;
}

/// ---------------------------------------------------------------------------
/// 디자인 시스템: 색상 · 그림자 · 공용 입력 필드 스타일
/// ---------------------------------------------------------------------------
class AppColors {
  static const Color primary = Color(0xFF4E5AE8);
  static const Color primaryDark = Color(0xFF3A46C8);
  static const Color bg = Color(0xFFF4F5FA);
  static const Color surface = Colors.white;
  static const Color ink = Color(0xFF1B1D28);
  static const Color inkMuted = Color(0xFF767A8A);
  static const Color line = Color(0xFFECEDF3);
  static const Color foundBg = Color(0xFFE6F7EC);
  static const Color foundFg = Color(0xFF1FA45A);
  static const Color lostBg = Color(0xFFFDECEE);
  static const Color lostFg = Color(0xFFE24C60);
  static const Color danger = Color(0xFFE24C60);
}

/// 카드/시트에 쓰는 부드러운 그림자.
const List<BoxShadow> kSoftShadow = [
  BoxShadow(color: Color(0x0F1B1D28), blurRadius: 18, offset: Offset(0, 6)),
];

/// 브랜드 그라데이션 (로고·강조 영역).
const LinearGradient kBrandGradient = LinearGradient(
  begin: Alignment.topLeft,
  end: Alignment.bottomRight,
  colors: [Color(0xFF5B67F2), Color(0xFF7C4DFF)],
);

/// 앱 전역에서 공유하는 입력 필드 데코레이션.
InputDecoration appInputDecoration(
  String label, {
  String? hint,
  Widget? prefixIcon,
  Widget? suffixIcon,
}) {
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
    borderRadius: BorderRadius.circular(14),
    borderSide: BorderSide(color: c, width: w),
  );
  return InputDecoration(
    labelText: label,
    hintText: hint,
    prefixIcon: prefixIcon,
    suffixIcon: suffixIcon,
    filled: true,
    fillColor: AppColors.surface,
    hintStyle: const TextStyle(color: Color(0xFFB4B7C4)),
    labelStyle: const TextStyle(color: AppColors.inkMuted),
    floatingLabelStyle: const TextStyle(
      color: AppColors.primary,
      fontWeight: FontWeight.w600,
    ),
    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
    border: border(AppColors.line),
    enabledBorder: border(AppColors.line),
    focusedBorder: border(AppColors.primary, 1.6),
    errorBorder: border(AppColors.lostFg),
    focusedErrorBorder: border(AppColors.lostFg, 1.6),
  );
}

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);
  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
    );
    return MaterialApp(
      title: '여기있대!',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: base.copyWith(surface: AppColors.surface),
        scaffoldBackgroundColor: AppColors.bg,
        textTheme: const TextTheme().apply(
          bodyColor: AppColors.ink,
          displayColor: AppColors.ink,
        ),
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bg,
          foregroundColor: AppColors.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          titleTextStyle: TextStyle(
            color: AppColors.ink,
            fontSize: 20,
            fontWeight: FontWeight.w800,
          ),
        ),
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            elevation: 0,
            minimumSize: const Size.fromHeight(54),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.line),
            minimumSize: const Size.fromHeight(50),
            textStyle: const TextStyle(
              fontSize: 15,
              fontWeight: FontWeight.w600,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
            ),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          elevation: 2,
          highlightElevation: 2,
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(20),
          ),
          titleTextStyle: const TextStyle(
            color: AppColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
          ),
          contentTextStyle: const TextStyle(
            color: AppColors.inkMuted,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.ink,
          contentTextStyle: const TextStyle(color: Colors.white),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          elevation: 0,
          height: 66,
          indicatorColor: AppColors.primary.withValues(alpha: 0.12),
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? AppColors.primary
                  : AppColors.inkMuted,
            ),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.line,
          thickness: 1,
        ),
      ),
      home: const AuthGate(),
    );
  }
}

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
        return const MainNavScreen();
      },
    );
  }
}

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
    final studentId = value?.trim() ?? '';
    if (studentId.isEmpty) return '학번을 입력해주세요.';
    if (!RegExp(r'^\d{6,10}$').hasMatch(studentId)) {
      return '학번은 숫자 6~10자로 입력해주세요.';
    }
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
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('저장하지 못했습니다: $e')));
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
          padding: const EdgeInsets.all(20),
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
                TextFormField(
                  controller: _departmentController,
                  validator: _validateDepartment,
                  decoration: appInputDecoration('학과', hint: ''),
                ),
                const SizedBox(height: 14),
                TextFormField(
                  controller: _studentIdController,
                  keyboardType: TextInputType.number,
                  validator: _validateStudentId,
                  decoration: appInputDecoration('학번 또는 사번', hint: '숫자만 입력'),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isSubmitting ? null : _submit,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
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
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// 로그인 후 하단 네비게이션바로 전환되는 메인 화면 (홈/내 글/채팅/마이페이지).
class MainNavScreen extends StatefulWidget {
  const MainNavScreen({super.key});

  @override
  State<MainNavScreen> createState() => _MainNavScreenState();
}

class _MainNavScreenState extends State<MainNavScreen> {
  int _currentIndex = 0;

  // 채팅 목록 화면(ChatListScreen)의 안읽음 판정 로직과 동일하게,
  // "나간 뒤 새 메시지 없는 채팅은 제외 + 마지막 메시지가 내가 마지막으로
  // 읽은 시각보다 나중이면 안읽음"으로 판단한다.
  bool _hasUnreadChat(
    List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs,
    String? uid,
  ) {
    if (docs == null || uid == null) return false;
    for (final doc in docs) {
      final data = doc.data();
      final clearedAt = Map<String, dynamic>.from(
        data['clearedAt'] as Map? ?? {},
      );
      final myClearedAt = clearedAt[uid] as Timestamp?;
      final lastMessageAt = data['lastMessageAt'] as Timestamp?;
      final isCleared =
          myClearedAt != null &&
          (lastMessageAt == null || lastMessageAt.compareTo(myClearedAt) <= 0);
      if (isCleared) continue;

      final lastMessage = data['lastMessage'] as String? ?? '';
      final lastReadAt = Map<String, dynamic>.from(
        data['lastReadAt'] as Map? ?? {},
      );
      final myLastRead = lastReadAt[uid] as Timestamp?;
      final isUnread =
          lastMessage.isNotEmpty &&
          lastMessageAt != null &&
          (myLastRead == null || lastMessageAt.compareTo(myLastRead) > 0);
      if (isUnread) return true;
    }
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    // 채팅 목록(ChatListScreen)과 하단 배지가 같은 chats 쿼리를 각자
    // 구독하면 실시간 리스너가 중복되므로, 여기서 한 번만 구독하고
    // 결과를 두 곳 모두에 내려준다.
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: uid)
          .snapshots(),
      builder: (context, snapshot) {
        final hasUnread = _hasUnreadChat(snapshot.data?.docs, uid);
        final tabs = [
          const HomeFeedScreen(),
          const MyPostsScreen(),
          ChatListScreen(
            docs: snapshot.data?.docs,
            hasError: snapshot.hasError,
          ),
          const ProfileScreen(),
        ];
        return Scaffold(
          body: IndexedStack(index: _currentIndex, children: tabs),
          bottomNavigationBar: Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: NavigationBar(
              selectedIndex: _currentIndex,
              onDestinationSelected: (index) =>
                  setState(() => _currentIndex = index),
              destinations: [
                const NavigationDestination(
                  icon: Icon(Icons.home_outlined, color: AppColors.inkMuted),
                  selectedIcon: Icon(
                    Icons.home_rounded,
                    color: AppColors.primary,
                  ),
                  label: '홈',
                ),
                const NavigationDestination(
                  icon: Icon(
                    Icons.receipt_long_outlined,
                    color: AppColors.inkMuted,
                  ),
                  selectedIcon: Icon(
                    Icons.receipt_long,
                    color: AppColors.primary,
                  ),
                  label: '내 글',
                ),
                NavigationDestination(
                  icon: Badge(
                    isLabelVisible: hasUnread,
                    smallSize: 9,
                    backgroundColor: AppColors.danger,
                    child: const Icon(
                      Icons.chat_bubble_outline_rounded,
                      color: AppColors.inkMuted,
                    ),
                  ),
                  selectedIcon: Badge(
                    isLabelVisible: hasUnread,
                    smallSize: 9,
                    backgroundColor: AppColors.danger,
                    child: const Icon(
                      Icons.chat_bubble_rounded,
                      color: AppColors.primary,
                    ),
                  ),
                  label: '채팅',
                ),
                const NavigationDestination(
                  icon: Icon(
                    Icons.person_outline_rounded,
                    color: AppColors.inkMuted,
                  ),
                  selectedIcon: Icon(
                    Icons.person_rounded,
                    color: AppColors.primary,
                  ),
                  label: '마이페이지',
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

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

  String? _validateEmail(String? value) {
    final email = value?.trim() ?? '';
    if (email.isEmpty) return '이메일을 입력해주세요.';
    if (!email.toLowerCase().endsWith(kAllowedEmailDomain)) {
      return '한림대학교 웹메일($kAllowedEmailDomain)만 사용할 수 있습니다.';
    }
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
    final email = _emailController.text.trim();
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
        builder: (context) =>
            PasswordResetScreen(initialEmail: _emailController.text.trim()),
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
                  Container(
                    width: 76,
                    height: 76,
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      gradient: kBrandGradient,
                      borderRadius: BorderRadius.circular(22),
                      boxShadow: [
                        BoxShadow(
                          color: AppColors.primary.withValues(alpha: 0.35),
                          blurRadius: 20,
                          offset: const Offset(0, 8),
                        ),
                      ],
                    ),
                    child: const Icon(
                      Icons.travel_explore_rounded,
                      color: Colors.white,
                      size: 38,
                    ),
                  ),
                  const SizedBox(height: 22),
                  const Text(
                    '여기있대!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      fontSize: 26,
                      fontWeight: FontWeight.w800,
                      letterSpacing: -0.5,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    '한림대학교 캠퍼스 분실물 찾기\n$kAllowedEmailDomain 계정으로 시작하세요',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      fontSize: 13.5,
                      height: 1.5,
                      color: AppColors.inkMuted,
                    ),
                  ),
                  const SizedBox(height: 32),
                  TextFormField(
                    controller: _emailController,
                    keyboardType: TextInputType.emailAddress,
                    validator: _validateEmail,
                    decoration: _inputDecoration(
                      '학교 이메일',
                      hint: '학번$kAllowedEmailDomain',
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
                      style: TextStyle(fontSize: 12, color: Colors.grey[600]),
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
                            Checkbox(
                              value: _agreedToPrivacy,
                              activeColor: AppColors.primary,
                              visualDensity: VisualDensity.compact,
                              materialTapTargetSize:
                                  MaterialTapTargetSize.shrinkWrap,
                              onChanged: (value) {
                                setState(
                                  () => _agreedToPrivacy = value ?? false,
                                );
                              },
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

  InputDecoration _inputDecoration(String label, {required String hint}) =>
      appInputDecoration(label, hint: hint);
}

/// 이메일 인증 코드 발송/검증을 담당하는 Vercel 백엔드 주소
const String kVerifyBackendUrl = 'https://verifybackend-eight.vercel.app';

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
      throw _BackendException(decoded['error'] as String? ?? 'unknown');
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
    } on _BackendException catch (e) {
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
    } on _BackendException catch (e) {
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
                  style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                Text(
                  '$email 로 전송된 6자리 코드를 입력해주세요.',
                  textAlign: TextAlign.center,
                  style: const TextStyle(fontSize: 13, color: Colors.black54),
                ),
                const SizedBox(height: 28),
                TextField(
                  controller: _codeController,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  maxLength: 6,
                  style: const TextStyle(
                    fontSize: 24,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 8,
                  ),
                  decoration: InputDecoration(
                    counterText: '',
                    hintText: '------',
                    errorText: _errorText,
                    filled: true,
                    fillColor: Colors.white,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.line),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: BorderSide(color: AppColors.line),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(
                        color: AppColors.primary,
                        width: 1.5,
                      ),
                    ),
                  ),
                ),
                const SizedBox(height: 20),
                SizedBox(
                  width: double.infinity,
                  height: 52,
                  child: ElevatedButton(
                    onPressed: _isVerifying ? null : _verifyCode,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: AppColors.primary,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(12),
                      ),
                    ),
                    child: _isVerifying
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                            ),
                          )
                        : const Text(
                            '인증 확인',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
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
                    style: TextStyle(color: Colors.black54),
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

class _BackendException implements Exception {
  final String code;
  _BackendException(this.code);
}

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
    final response = await http.post(
      Uri.parse('$kVerifyBackendUrl$path'),
      headers: {'Content-Type': 'application/json'},
      body: jsonEncode(body),
    );
    final decoded = response.body.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(response.body) as Map<String, dynamic>;
    if (response.statusCode >= 400) {
      throw _BackendException(decoded['error'] as String? ?? 'unknown');
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
    } on _BackendException catch (e) {
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
    } on _BackendException catch (e) {
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
    } on _BackendException catch (e) {
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
          padding: const EdgeInsets.all(20),
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
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isSending ? null : _sendCode,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
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
            fontWeight: FontWeight.bold,
            letterSpacing: 8,
          ),
          decoration: InputDecoration(
            counterText: '',
            hintText: '------',
            errorText: _codeErrorText,
            filled: true,
            fillColor: Colors.white,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.line),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: AppColors.line),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: const BorderSide(
                color: AppColors.primary,
                width: 1.5,
              ),
            ),
          ),
        ),
        const SizedBox(height: 20),
        SizedBox(
          height: 52,
          child: ElevatedButton(
            onPressed: _isVerifyingCode ? null : _verifyCode,
            style: ElevatedButton.styleFrom(
              backgroundColor: AppColors.primary,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
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
          SizedBox(
            height: 52,
            child: ElevatedButton(
              onPressed: _isSubmitting ? null : _submitReset,
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
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
          ),
        ],
      ),
    );
  }
}

/// 글 종류
enum ItemType {
  found,
  lost;

  static ItemType fromValue(String value) => ItemType.values.firstWhere(
    (e) => e.name == value,
    orElse: () => ItemType.found,
  );
}

/// Firestore의 'items' 컬렉션 레퍼런스
final CollectionReference<Map<String, dynamic>> itemsCollection =
    FirebaseFirestore.instance.collection('items');

/// 주어진 시각을 "방금 전 / N분 전 / N시간 전 / 어제 / N일 전 / 날짜" 형태로 표시한다.
String relativeTime(DateTime? time) {
  if (time == null) return '';
  final diff = DateTime.now().difference(time);
  if (diff.inMinutes < 1) return '방금 전';
  if (diff.inMinutes < 60) return '${diff.inMinutes}분 전';
  if (diff.inHours < 24) return '${diff.inHours}시간 전';
  if (diff.inDays == 1) return '어제';
  if (diff.inDays < 7) return '${diff.inDays}일 전';
  return '${time.year}.${time.month.toString().padLeft(2, '0')}.${time.day.toString().padLeft(2, '0')}';
}

/// 물품 카테고리 목록 ('전체'는 필터용이며 게시글 카테고리로는 쓰이지 않음).
const List<String> kItemCategories = [
  '전자기기',
  '지갑/카드/현금',
  '가방',
  '의류',
  '도서/문구',
  '액세서리',
  '기타',
];

/// 신고가 이 횟수 이상 누적되면 일반 피드에서 자동으로 숨긴다.
const int kReportThreshold = 3;

/// 조회수가 이 값 이상이면 목록에 "인기" 배지를 붙인다.
const int kPopularViewThreshold = 20;

/// 분실물/습득물 게시글 데이터 모델
class LostFoundItem {
  final String? id;
  final String title;
  final String description;
  final String location;
  final String locationDetail;
  final ItemType type;
  final String category;
  final String authorUid;
  final String authorNickname;
  final bool resolved;
  final List<String> imageUrls;
  final DateTime? createdAt;
  final int reportCount;
  final int viewCount;

  bool get isHidden => reportCount >= kReportThreshold;

  LostFoundItem({
    this.id,
    required this.title,
    this.description = '',
    required this.location,
    this.locationDetail = '',
    required this.type,
    this.category = '기타',
    required this.authorUid,
    required this.authorNickname,
    this.resolved = false,
    this.imageUrls = const [],
    this.createdAt,
    this.reportCount = 0,
    this.viewCount = 0,
  });

  factory LostFoundItem.fromDoc(
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) {
    final data = doc.data();
    final urlsField = data['imageUrls'] as List?;
    final legacyUrl = data['imageUrl'] as String?;
    final imageUrls = urlsField != null
        ? urlsField.whereType<String>().toList()
        : (legacyUrl != null ? [legacyUrl] : <String>[]);
    return LostFoundItem(
      id: doc.id,
      title: data['title'] as String? ?? '',
      description: data['description'] as String? ?? '',
      location: data['location'] as String? ?? '',
      locationDetail: data['locationDetail'] as String? ?? '',
      type: ItemType.fromValue(data['type'] as String? ?? 'found'),
      category: data['category'] as String? ?? '기타',
      authorUid: data['authorUid'] as String? ?? '',
      authorNickname: data['authorNickname'] as String? ?? '익명',
      resolved: data['resolved'] as bool? ?? false,
      imageUrls: imageUrls,
      createdAt: (data['createdAt'] as Timestamp?)?.toDate(),
      reportCount: (data['reportCount'] as num?)?.toInt() ?? 0,
      viewCount: (data['viewCount'] as num?)?.toInt() ?? 0,
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'title': title,
      'description': description,
      'location': location,
      'locationDetail': locationDetail,
      'type': type.name,
      'category': category,
      'authorUid': authorUid,
      'authorNickname': authorNickname,
      'resolved': resolved,
      'imageUrls': imageUrls,
      'reportCount': 0,
      'viewCount': 0,
      'createdAt': FieldValue.serverTimestamp(),
    };
  }

  Map<String, dynamic> toUpdateMap() {
    return {
      'title': title,
      'description': description,
      'location': location,
      'locationDetail': locationDetail,
      'type': type.name,
      'category': category,
      'resolved': resolved,
      'imageUrls': imageUrls,
    };
  }
}

/// 이번 앱 세션에서 이미 조회수를 올린 게시글 id 모음 (중복 카운트 방지).
final Set<String> _viewedItemIdsThisSession = {};

/// 게시글 상세를 열 때 조회수를 1 증가시킨다. 작성자 본인의 조회는 세지 않고,
/// 같은 글을 이번 세션에서 여러 번 열어도 한 번만 센다.
void incrementItemViewCount(LostFoundItem item) {
  final myUid = FirebaseAuth.instance.currentUser?.uid;
  final itemId = item.id;
  if (myUid == null || myUid == item.authorUid || itemId == null) return;
  if (!_viewedItemIdsThisSession.add(itemId)) return;
  itemsCollection
      .doc(itemId)
      .update({'viewCount': FieldValue.increment(1)})
      .catchError((_) {});
}

class HomeFeedScreen extends StatefulWidget {
  const HomeFeedScreen({super.key});

  @override
  State<HomeFeedScreen> createState() => _HomeFeedScreenState();
}

class _HomeFeedScreenState extends State<HomeFeedScreen> {
  // 필터 상태: 0 = 전체, 1 = 습득물, 2 = 분실물
  int _selectedFilter = 0;
  // '전체'면 카테고리 필터를 적용하지 않는다.
  String _selectedCategory = '전체';
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';
  // 정렬 기준: false = 최신순, true = 조회순(인기순)
  bool _sortByPopular = false;

  static const int _pageSize = 20;
  int _loadedPages = 1;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<LostFoundItem> _applySearch(List<LostFoundItem> items) {
    var result = items.where((item) => !item.isHidden).toList();
    if (_selectedCategory != '전체') {
      result = result
          .where((item) => item.category == _selectedCategory)
          .toList();
    }
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return result;
    return result
        .where(
          (item) =>
              item.title.toLowerCase().contains(query) ||
              item.description.toLowerCase().contains(query),
        )
        .toList();
  }

  Query<Map<String, dynamic>> get _filteredQuery {
    Query<Map<String, dynamic>> query;
    switch (_selectedFilter) {
      case 1:
        query = itemsCollection.where('type', isEqualTo: ItemType.found.name);
      case 2:
        query = itemsCollection.where('type', isEqualTo: ItemType.lost.name);
      default:
        query = itemsCollection;
    }
    query = query.orderBy(
      _sortByPopular ? 'viewCount' : 'createdAt',
      descending: true,
    );
    // 검색 중에는 아직 페이지에 로드되지 않은 과거 게시글도 찾을 수 있어야
    // 하므로, 검색어가 있을 때는 페이지네이션 limit을 적용하지 않는다.
    if (_searchQuery.trim().isEmpty) {
      query = query.limit(_pageSize * _loadedPages);
    }
    return query;
  }

  void _goToRegisterScreen() {
    Navigator.push(
      context,
      MaterialPageRoute(builder: (context) => const RegisterItemScreen()),
    );
  }

  void _showDetail(LostFoundItem item) {
    incrementItemViewCount(item);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => ItemDetailSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 20,
        title: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: kBrandGradient,
                borderRadius: BorderRadius.circular(9),
              ),
              child: const Icon(
                Icons.travel_explore_rounded,
                color: Colors.white,
                size: 18,
              ),
            ),
            const SizedBox(width: 10),
            const Text('여기있대!'),
          ],
        ),
        actions: [
          PopupMenuButton<bool>(
            tooltip: '정렬',
            initialValue: _sortByPopular,
            onSelected: (value) => setState(() {
              _sortByPopular = value;
              _loadedPages = 1;
            }),
            icon: Icon(
              _sortByPopular
                  ? Icons.local_fire_department_rounded
                  : Icons.sort_rounded,
              color: AppColors.inkMuted,
            ),
            itemBuilder: (context) => const [
              PopupMenuItem(value: false, child: Text('최신순')),
              PopupMenuItem(value: true, child: Text('조회순')),
            ],
          ),
          const _NotificationBellButton(),
          const SizedBox(width: 12),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
            child: TextField(
              controller: _searchController,
              onChanged: (value) => setState(() => _searchQuery = value),
              decoration: InputDecoration(
                hintText: '제목이나 설명으로 검색',
                hintStyle: const TextStyle(color: Color(0xFFB4B7C4)),
                prefixIcon: const Icon(
                  Icons.search_rounded,
                  color: AppColors.inkMuted,
                ),
                suffixIcon: _searchQuery.isEmpty
                    ? null
                    : IconButton(
                        icon: const Icon(
                          Icons.close_rounded,
                          color: AppColors.inkMuted,
                        ),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      ),
                filled: true,
                fillColor: AppColors.surface,
                contentPadding: const EdgeInsets.symmetric(vertical: 0),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(color: AppColors.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(30),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
          ),
          _buildFilterChips(),
          Expanded(
            child: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
              stream: _filteredQuery.snapshots(),
              builder: (context, snapshot) {
                if (snapshot.hasError) {
                  return _FeedMessage(
                    icon: Icons.error_outline_rounded,
                    text: '데이터를 불러오지 못했습니다.',
                  );
                }
                if (!snapshot.hasData) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }

                final docs = snapshot.data!.docs;
                final visibleItems = docs
                    .map(LostFoundItem.fromDoc)
                    .where((item) => !item.isHidden)
                    .toList();
                // 카테고리 칩 개수는 지금 로드된(페이지네이션된) 목록 기준이라,
                // 아직 불러오지 않은 과거 게시글은 반영되지 않을 수 있다.
                final categoryCounts = <String, int>{};
                for (final item in visibleItems) {
                  categoryCounts[item.category] =
                      (categoryCounts[item.category] ?? 0) + 1;
                }
                final items = _applySearch(visibleItems);
                // 검색 중에는 limit 없이 전체를 이미 불러온 상태이므로 더보기가 필요 없다.
                // 그 외에는 받은 문서 수가 요청한 개수(limit)와 같으면 더 남아있을 가능성이 있다고 본다.
                final canLoadMore =
                    _searchQuery.trim().isEmpty &&
                    docs.length == _pageSize * _loadedPages;

                return Column(
                  children: [
                    _buildCategoryChips(categoryCounts),
                    const SizedBox(height: 4),
                    Expanded(
                      child: items.isEmpty
                          ? _FeedMessage(
                              icon: _searchQuery.isEmpty
                                  ? Icons.inbox_outlined
                                  : Icons.search_off_rounded,
                              text: _searchQuery.isEmpty
                                  ? '아직 등록된 게시글이 없어요.\n첫 게시글을 등록해보세요!'
                                  : '검색 결과가 없습니다.',
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(
                                20,
                                8,
                                20,
                                100,
                              ),
                              itemCount: items.length + (canLoadMore ? 1 : 0),
                              itemBuilder: (context, index) {
                                if (index == items.length) {
                                  return Padding(
                                    padding: const EdgeInsets.symmetric(
                                      vertical: 16,
                                    ),
                                    child: Center(
                                      child: OutlinedButton(
                                        onPressed: () =>
                                            setState(() => _loadedPages += 1),
                                        child: const Text('더 보기'),
                                      ),
                                    ),
                                  );
                                }
                                final item = items[index];
                                return _ItemCard(
                                  item: item,
                                  onTap: () => _showDetail(item),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _goToRegisterScreen,
        icon: const Icon(Icons.edit_outlined),
        label: const Text(
          '등록하기',
          style: TextStyle(fontWeight: FontWeight.w700),
        ),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    );
  }

  Widget _buildFilterChips() {
    const labels = ['전체', '습득물', '분실물'];
    return SizedBox(
      height: 52,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
        itemCount: labels.length,
        separatorBuilder: (context, index) => const SizedBox(width: 8),
        itemBuilder: (context, index) {
          final selected = _selectedFilter == index;
          return GestureDetector(
            onTap: () => setState(() {
              _selectedFilter = index;
              _loadedPages = 1;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 18),
              decoration: BoxDecoration(
                color: selected ? AppColors.primary : AppColors.surface,
                borderRadius: BorderRadius.circular(30),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.line,
                ),
              ),
              child: Text(
                labels[index],
                style: TextStyle(
                  color: selected ? Colors.white : AppColors.inkMuted,
                  fontWeight: FontWeight.w700,
                  fontSize: 13.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildCategoryChips(Map<String, int> categoryCounts) {
    final labels = ['전체', ...kItemCategories];
    final totalCount = categoryCounts.values.fold(0, (a, b) => a + b);
    return SizedBox(
      height: 44,
      child: ListView.separated(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
        itemCount: labels.length,
        separatorBuilder: (context, index) => const SizedBox(width: 6),
        itemBuilder: (context, index) {
          final label = labels[index];
          final selected = _selectedCategory == label;
          final count = label == '전체'
              ? totalCount
              : (categoryCounts[label] ?? 0);
          return GestureDetector(
            onTap: () => setState(() {
              _selectedCategory = label;
              _loadedPages = 1;
            }),
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 180),
              alignment: Alignment.center,
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: selected
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : AppColors.surface,
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: selected ? AppColors.primary : AppColors.line,
                ),
              ),
              child: Text(
                count > 0 ? '$label ($count)' : label,
                style: TextStyle(
                  color: selected ? AppColors.primary : AppColors.inkMuted,
                  fontWeight: FontWeight.w600,
                  fontSize: 12.5,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

/// 피드 빈 상태·오류 메시지 (아이콘 + 안내 문구).
class _FeedMessage extends StatelessWidget {
  final IconData icon;
  final String text;

  const _FeedMessage({required this.icon, required this.text});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 52, color: const Color(0xFFC7CAD6)),
          const SizedBox(height: 14),
          Text(
            text,
            textAlign: TextAlign.center,
            style: const TextStyle(
              color: AppColors.inkMuted,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}

/// 화면: 내가 등록한 글 모아보기
class MyPostsScreen extends StatefulWidget {
  const MyPostsScreen({super.key});

  @override
  State<MyPostsScreen> createState() => _MyPostsScreenState();
}

class _MyPostsScreenState extends State<MyPostsScreen> {
  static const int _pageSize = 20;
  int _loadedPages = 1;

  void _showDetail(BuildContext context, LostFoundItem item) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (context) => ItemDetailSheet(item: item),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('내 글', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: itemsCollection
            .where('authorUid', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .limit(_pageSize * _loadedPages)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _FeedMessage(
              icon: Icons.error_outline_rounded,
              text: '내 글을 불러오지 못했습니다.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final docs = snapshot.data!.docs;
          final items = docs.map(LostFoundItem.fromDoc).toList();
          final canLoadMore = docs.length == _pageSize * _loadedPages;
          if (items.isEmpty) {
            return const _FeedMessage(
              icon: Icons.receipt_long_outlined,
              text: '아직 등록한 글이 없어요.\n첫 게시글을 등록해보세요!',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: items.length + (canLoadMore ? 1 : 0),
            itemBuilder: (context, index) {
              if (index == items.length) {
                return Padding(
                  padding: const EdgeInsets.symmetric(vertical: 16),
                  child: Center(
                    child: OutlinedButton(
                      onPressed: () => setState(() => _loadedPages += 1),
                      child: const Text('더 보기'),
                    ),
                  ),
                );
              }
              final item = items[index];
              return _ItemCard(
                item: item,
                onTap: () => _showDetail(context, item),
              );
            },
          );
        },
      ),
    );
  }
}

/// 화면: 마이페이지 (닉네임 관리, 차단 관리, 로그아웃, 회원 탈퇴)
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isDeleting = false;

  /// 닉네임은 게시글(authorNickname), 채팅방(participantNicknames)에 생성 시점
  /// 스냅샷으로 저장돼 있어 그대로면 과거 기록에 옛 닉네임이 남는다. 내가
  /// 소유한(작성자이거나 참여자인) 문서만 골라 새 닉네임으로 맞춰준다.
  Future<void> _propagateNicknameChange(String uid, String newNickname) async {
    final myItems = await itemsCollection
        .where('authorUid', isEqualTo: uid)
        .get();
    final myChats = await FirebaseFirestore.instance
        .collection('chats')
        .where('participants', arrayContains: uid)
        .get();

    final writes =
        <(DocumentReference<Map<String, dynamic>>, Map<String, dynamic>)>[
          for (final doc in myItems.docs)
            (doc.reference, {'authorNickname': newNickname}),
          for (final doc in myChats.docs)
            (doc.reference, {'participantNicknames.$uid': newNickname}),
        ];

    const chunkSize = 450;
    for (var i = 0; i < writes.length; i += chunkSize) {
      final chunk = writes.sublist(
        i,
        (i + chunkSize) > writes.length ? writes.length : i + chunkSize,
      );
      final batch = FirebaseFirestore.instance.batch();
      for (final (ref, data) in chunk) {
        batch.update(ref, data);
      }
      await batch.commit();
    }
  }

  Future<void> _editNickname() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final nicknameController = TextEditingController(
      text: user.displayName ?? '',
    );
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              title: const Text('닉네임 변경'),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: nicknameController,
                  autofocus: true,
                  validator: (value) {
                    final v = value?.trim() ?? '';
                    if (v.isEmpty) return '닉네임을 입력해주세요.';
                    if (v.length > 12) return '닉네임은 12자 이하로 입력해주세요.';
                    return null;
                  },
                  decoration: const InputDecoration(labelText: '닉네임'),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () => Navigator.pop(dialogContext),
                  child: const Text('취소'),
                ),
                TextButton(
                  onPressed: isSaving
                      ? null
                      : () async {
                          if (!formKey.currentState!.validate()) return;
                          setDialogState(() => isSaving = true);
                          try {
                            final newNickname = nicknameController.text.trim();
                            await user.updateDisplayName(newNickname);
                            await user.reload();
                            try {
                              await _propagateNicknameChange(
                                user.uid,
                                newNickname,
                              );
                            } catch (_) {
                              // 전파 실패는 무시한다 - 새로 쓰는 글/채팅부터는
                              // 어차피 최신 닉네임이 반영되므로 치명적이지 않다.
                            }
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            if (mounted) setState(() {});
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(content: Text('변경에 실패했습니다: $e')),
                              );
                            }
                          }
                        },
                  child: isSaving
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Text('저장'),
                ),
              ],
            );
          },
        );
      },
    );
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('로그아웃'),
        content: const Text('정말 로그아웃하시겠습니까?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text(
              '로그아웃',
              style: TextStyle(color: AppColors.danger),
            ),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await FirebaseAuth.instance.signOut();
    }
  }

  Future<void> _deleteAccount() async {
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Text('회원 탈퇴'),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  '탈퇴 시 계정과 내가 작성한 게시글이 모두 삭제되며,\n되돌릴 수 없습니다.\n계속하려면 비밀번호를 입력해주세요.',
                ),
                const SizedBox(height: 16),
                TextFormField(
                  controller: passwordController,
                  obscureText: true,
                  validator: (value) =>
                      (value == null || value.isEmpty) ? '비밀번호를 입력해주세요.' : null,
                  decoration: const InputDecoration(labelText: '비밀번호'),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('취소'),
            ),
            TextButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogContext, true);
              },
              child: const Text(
                '탈퇴하기',
                style: TextStyle(color: AppColors.danger),
              ),
            ),
          ],
        );
      },
    );

    if (confirmed != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    setState(() => _isDeleting = true);

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: passwordController.text,
      );
      await user.reauthenticateWithCredential(credential);

      // reports는 클라이언트가 읽기/쓰기 전부 차단되어 있어(신고 사유 비공개,
      // 위변조 방지) 직접 지울 수 없다. Admin SDK를 쓰는 백엔드에 대신 요청한다.
      // 실패해도 계정 삭제 자체를 막을 정도는 아니므로 조용히 넘어간다.
      try {
        final idToken = await user.getIdToken();
        await http.post(
          Uri.parse('$kVerifyBackendUrl/api/delete-my-reports'),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $idToken',
          },
        );
      } catch (_) {}

      final myItems = await itemsCollection
          .where('authorUid', isEqualTo: user.uid)
          .get();
      final myChats = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: user.uid)
          .get();
      final myNotifications = await FirebaseFirestore.instance
          .collection('notifications')
          .where('recipientUid', isEqualTo: user.uid)
          .get();

      // 채팅방 문서만 지우면 messages 서브컬렉션은 Firestore가 자동으로
      // 지워주지 않으므로, 각 채팅방의 메시지를 먼저 모아서 함께 삭제한다.
      final messageRefs = <DocumentReference<Map<String, dynamic>>>[];
      for (final chatDoc in myChats.docs) {
        final messages = await chatDoc.reference.collection('messages').get();
        messageRefs.addAll(messages.docs.map((m) => m.reference));
      }

      // messages는 부모 채팅방 문서가 아직 존재해야 삭제 규칙을 통과하므로,
      // 여러 청크로 나뉘더라도 항상 채팅방 문서보다 먼저 삭제되도록 앞에 둔다.
      final refsToDelete = <DocumentReference>[
        ...messageRefs,
        ...myItems.docs.map((d) => d.reference),
        ...myChats.docs.map((d) => d.reference),
        ...myNotifications.docs.map((d) => d.reference),
      ];

      // Firestore 배치는 최대 500개 작업까지만 허용하므로 청크로 나눠 커밋한다.
      const chunkSize = 450;
      for (var i = 0; i < refsToDelete.length; i += chunkSize) {
        final chunk = refsToDelete.sublist(
          i,
          (i + chunkSize) > refsToDelete.length
              ? refsToDelete.length
              : i + chunkSize,
        );
        final batch = FirebaseFirestore.instance.batch();
        for (final ref in chunk) {
          batch.delete(ref);
        }
        await batch.commit();
      }

      await FirebaseFirestore.instance
          .collection('userPrivate')
          .doc(user.uid)
          .delete();
      await FirebaseFirestore.instance
          .collection('blocks')
          .doc(user.uid)
          .delete();

      await user.delete();
    } on FirebaseAuthException catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        final message =
            e.code == 'wrong-password' || e.code == 'invalid-credential'
            ? '비밀번호가 올바르지 않습니다.'
            : '탈퇴 처리 중 오류가 발생했습니다: ${e.message}';
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(message)));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isDeleting = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('탈퇴 처리 중 오류가 발생했습니다: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text(
          '마이페이지',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: _isDeleting
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : ListView(
              padding: const EdgeInsets.all(20),
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: AppColors.surface,
                    borderRadius: BorderRadius.circular(18),
                    boxShadow: kSoftShadow,
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 58,
                        height: 58,
                        alignment: Alignment.center,
                        decoration: BoxDecoration(
                          gradient: kBrandGradient,
                          borderRadius: BorderRadius.circular(18),
                        ),
                        child: Text(
                          (user?.displayName?.trim().isNotEmpty ?? false)
                              ? user!.displayName!.trim().characters.first
                              : '?',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 24,
                            fontWeight: FontWeight.w800,
                          ),
                        ),
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ?? '익명',
                              style: const TextStyle(
                                fontSize: 18,
                                fontWeight: FontWeight.w800,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 4),
                            Text(
                              user?.email ?? '',
                              style: const TextStyle(
                                fontSize: 13,
                                color: AppColors.inkMuted,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        icon: const Icon(
                          Icons.edit_outlined,
                          color: AppColors.inkMuted,
                        ),
                        tooltip: '닉네임 변경',
                        onPressed: _editNickname,
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 20),
                _ProfileMenuTile(
                  icon: Icons.block_outlined,
                  label: '차단 관리',
                  onTap: () {
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => const BlockedUsersScreen(),
                      ),
                    );
                  },
                ),
                const SizedBox(height: 12),
                _ProfileMenuTile(
                  icon: Icons.logout_rounded,
                  label: '로그아웃',
                  onTap: _confirmLogout,
                ),
                const SizedBox(height: 12),
                _ProfileMenuTile(
                  icon: Icons.person_remove_outlined,
                  label: '회원 탈퇴',
                  labelColor: AppColors.danger,
                  onTap: _deleteAccount,
                ),
              ],
            ),
    );
  }
}

class _ProfileMenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? labelColor;
  final VoidCallback onTap;

  const _ProfileMenuTile({
    required this.icon,
    required this.label,
    required this.onTap,
    this.labelColor,
  });

  @override
  Widget build(BuildContext context) {
    final color = labelColor ?? AppColors.ink;
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: kSoftShadow,
      ),
      child: ListTile(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        leading: Icon(icon, color: color),
        title: Text(
          label,
          style: TextStyle(color: color, fontWeight: FontWeight.w600),
        ),
        trailing: const Icon(
          Icons.chevron_right_rounded,
          color: Color(0xFFC7CAD6),
        ),
        onTap: onTap,
      ),
    );
  }
}

class _ItemCard extends StatelessWidget {
  final LostFoundItem item;
  final VoidCallback onTap;

  const _ItemCard({required this.item, required this.onTap});

  Widget _thumbnail() {
    Widget placeholder(IconData icon) => Container(
      width: 64,
      height: 64,
      color: AppColors.primary.withValues(alpha: 0.08),
      child: Icon(icon, color: AppColors.primary),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: item.imageUrls.isNotEmpty
          ? Image.network(
              item.imageUrls.first,
              width: 64,
              height: 64,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) =>
                  placeholder(Icons.broken_image_outlined),
            )
          : placeholder(Icons.inventory_2_outlined),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(18),
        boxShadow: kSoftShadow,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          borderRadius: BorderRadius.circular(18),
          onTap: onTap,
          child: Opacity(
            opacity: item.resolved ? 0.6 : 1.0,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _thumbnail(),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            _StatusBadge(type: item.type),
                            if (item.viewCount >= kPopularViewThreshold) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFFFF3E0),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Icon(
                                      Icons.local_fire_department_rounded,
                                      size: 11,
                                      color: Color(0xFFE8862E),
                                    ),
                                    SizedBox(width: 2),
                                    Text(
                                      '인기',
                                      style: TextStyle(
                                        color: Color(0xFFE8862E),
                                        fontSize: 11,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            if (item.resolved) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFEDEEF3),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '거래완료',
                                  style: TextStyle(
                                    color: AppColors.inkMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                            if (item.isHidden) ...[
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 9,
                                  vertical: 4,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.danger.withValues(
                                    alpha: 0.1,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Text(
                                  '신고로 숨김 처리됨',
                                  style: TextStyle(
                                    color: AppColors.danger,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w700,
                                  ),
                                ),
                              ),
                            ],
                            const SizedBox(width: 6),
                            Flexible(
                              child: Text(
                                item.category,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 11,
                                  color: AppColors.inkMuted,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 7),
                        Text(
                          item.title,
                          style: const TextStyle(
                            fontSize: 15.5,
                            fontWeight: FontWeight.w700,
                            color: AppColors.ink,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: 6),
                        Row(
                          children: [
                            const Icon(
                              Icons.place_outlined,
                              size: 14,
                              color: AppColors.inkMuted,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                item.location,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ),
                            const SizedBox(width: 10),
                            const Icon(
                              Icons.person_outline,
                              size: 14,
                              color: AppColors.inkMuted,
                            ),
                            const SizedBox(width: 3),
                            Flexible(
                              child: Text(
                                item.authorNickname,
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                  fontSize: 12.5,
                                  color: AppColors.inkMuted,
                                ),
                              ),
                            ),
                          ],
                        ),
                        if (item.createdAt != null || item.viewCount > 0) ...[
                          const SizedBox(height: 4),
                          Text(
                            [
                              if (item.createdAt != null)
                                relativeTime(item.createdAt),
                              if (item.viewCount > 0) '조회 ${item.viewCount}',
                            ].join(' · '),
                            style: const TextStyle(
                              fontSize: 11.5,
                              color: Color(0xFFB4B7C4),
                            ),
                          ),
                        ],
                      ],
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

class _StatusBadge extends StatelessWidget {
  final ItemType type;

  const _StatusBadge({required this.type});

  @override
  Widget build(BuildContext context) {
    final isFound = type == ItemType.found;
    final bgColor = isFound ? AppColors.foundBg : AppColors.lostBg;
    final fgColor = isFound ? AppColors.foundFg : AppColors.lostFg;
    final label = isFound ? '습득물' : '분실물';
    final icon = isFound
        ? Icons.volunteer_activism_rounded
        : Icons.search_rounded;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
      decoration: BoxDecoration(
        color: bgColor,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 12, color: fgColor),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              color: fgColor,
              fontSize: 11.5,
              fontWeight: FontWeight.w700,
            ),
          ),
        ],
      ),
    );
  }
}

/// 화면 B: 분실물/습득물 등록 폼 (editingItem이 있으면 수정 모드)
class RegisterItemScreen extends StatefulWidget {
  final LostFoundItem? editingItem;

  const RegisterItemScreen({super.key, this.editingItem});

  @override
  State<RegisterItemScreen> createState() => _RegisterItemScreenState();
}

class _RegisterItemScreenState extends State<RegisterItemScreen> {
  final TextEditingController _titleController = TextEditingController();
  final TextEditingController _descriptionController = TextEditingController();
  final TextEditingController _locationDetailController =
      TextEditingController();

  ItemType _selectedType = ItemType.found;
  String _selectedCategory = kItemCategories.last;
  bool _isSubmitting = false;

  static const int _maxImages = 5;
  final List<XFile> _newImages = [];
  final List<Uint8List> _newImageBytes = [];
  List<String> _existingImageUrls = [];

  int get _totalImageCount => _existingImageUrls.length + _newImages.length;

  static const List<String> _locations = [
    '(1) 공학관',
    '(2) 대학본부-인문1관',
    '(3) 의학관',
    '(4) 인문2관',
    '(5) 대학본부별관',
    '(6) 실험동물센터',
    '(7) 자연과학관',
    '(8) 생명과학관',
    '(9) Campus Life Center',
    '(10) 사회경영1관',
    '(11) 일송아트홀',
    '(12) 창업보육센터',
    '(13) 사회경영2관',
    '(14) 국제관',
    '(15) 국제회의관',
    '(16) 기초교육관',
    '(17) 일송창의비전관',
    '(18) 한림레크리에이션센터',
    '(19) 학군단',
    '(20) 실내테니스장',
    '(21) 한림중개의과학연구원',
    '(22) 산학협력관',
    '(23) 도헌글로벌스쿨',
    '(24) 학생생활관 1관',
    '(25) 학생생활관 2관',
    '(26) 학생생활관 3관',
    '(27) 학생생활관 4관',
    '(28) 학생생활관 5관',
    '(29) 학생생활관 6관',
    '(30) 학생생활관 7관',
    '(31) 학생생활관 8관',
    '(32) 체육 기자재실',
    '(33) H Stadium',
    '(34) IL Song Stadium',
    '(35) 씨름장',
    '(36) 온실',
    '(37) 한림대학교 춘천성심병원',
  ];
  late String _selectedLocation;

  bool get _isEditing => widget.editingItem != null;

  @override
  void initState() {
    super.initState();
    final editing = widget.editingItem;
    if (editing != null) {
      _titleController.text = editing.title;
      _descriptionController.text = editing.description;
      _locationDetailController.text = editing.locationDetail;
      _selectedType = editing.type;
      _selectedCategory = kItemCategories.contains(editing.category)
          ? editing.category
          : kItemCategories.last;
      _selectedLocation = _locations.contains(editing.location)
          ? editing.location
          : _locations.first;
      _existingImageUrls = List.of(editing.imageUrls);
    } else {
      _selectedLocation = _locations.first;
    }
  }

  Future<void> _pickImages() async {
    final remaining = _maxImages - _totalImageCount;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('사진은 최대 $_maxImages장까지 첨부할 수 있어요.')),
      );
      return;
    }
    final picked = await ImagePicker().pickMultiImage(
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (picked.isEmpty) return;
    final selected = picked.take(remaining).toList();
    final bytesList = await Future.wait(selected.map((f) => f.readAsBytes()));
    setState(() {
      _newImages.addAll(selected);
      _newImageBytes.addAll(bytesList);
    });
  }

  void _removeExistingImage(int index) {
    setState(() => _existingImageUrls.removeAt(index));
  }

  void _removeNewImage(int index) {
    setState(() {
      _newImages.removeAt(index);
      _newImageBytes.removeAt(index);
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationDetailController.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final title = _titleController.text.trim();
    if (title.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('물건 이름을 입력해주세요.')));
      return;
    }

    setState(() => _isSubmitting = true);

    final description = _descriptionController.text.trim();
    final locationDetail = _locationDetailController.text.trim();

    try {
      final uploadedUrls = <String>[];
      for (final file in _newImages) {
        uploadedUrls.add(await uploadImageToCloudinary(file));
      }
      final imageUrls = [..._existingImageUrls, ...uploadedUrls];

      if (_isEditing) {
        final editing = widget.editingItem!;
        final updatedItem = LostFoundItem(
          id: editing.id,
          title: title,
          description: description,
          location: _selectedLocation,
          locationDetail: locationDetail,
          type: _selectedType,
          category: _selectedCategory,
          authorUid: editing.authorUid,
          authorNickname: editing.authorNickname,
          resolved: editing.resolved,
          imageUrls: imageUrls,
        );
        await itemsCollection
            .doc(updatedItem.id)
            .update(updatedItem.toUpdateMap());
      } else {
        final user = FirebaseAuth.instance.currentUser!;
        final newItem = LostFoundItem(
          title: title,
          description: description,
          location: _selectedLocation,
          locationDetail: locationDetail,
          type: _selectedType,
          category: _selectedCategory,
          authorUid: user.uid,
          authorNickname: user.displayName ?? '익명',
          imageUrls: imageUrls,
        );
        await itemsCollection.add(newItem.toMap());
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('${_isEditing ? '수정' : '등록'}에 실패했습니다: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: Text(_isEditing ? '글 수정' : '글쓰기'),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '사진 ($_totalImageCount/$_maxImages)',
              style: const TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w600,
                color: AppColors.ink,
              ),
            ),
            const SizedBox(height: 10),
            SizedBox(
              height: 92,
              child: ListView(
                scrollDirection: Axis.horizontal,
                children: [
                  for (var i = 0; i < _existingImageUrls.length; i++)
                    _ImagePickerTile(
                      key: ValueKey('existing_$i'),
                      onRemove: () => _removeExistingImage(i),
                      child: Image.network(
                        _existingImageUrls[i],
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                        errorBuilder: (context, error, stackTrace) =>
                            const Icon(
                              Icons.broken_image_outlined,
                              color: Color(0xFFC7CAD6),
                            ),
                      ),
                    ),
                  for (var i = 0; i < _newImageBytes.length; i++)
                    _ImagePickerTile(
                      key: ValueKey('new_$i'),
                      onRemove: () => _removeNewImage(i),
                      child: Image.memory(
                        _newImageBytes[i],
                        width: 88,
                        height: 88,
                        fit: BoxFit.cover,
                      ),
                    ),
                  if (_totalImageCount < _maxImages)
                    GestureDetector(
                      onTap: _pickImages,
                      child: Container(
                        width: 88,
                        height: 88,
                        margin: const EdgeInsets.only(right: 10),
                        decoration: BoxDecoration(
                          color: AppColors.surface,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: AppColors.line),
                        ),
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.add_photo_alternate_outlined,
                              color: AppColors.primary.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 4),
                            const Text(
                              '사진 추가',
                              style: TextStyle(
                                color: AppColors.inkMuted,
                                fontSize: 11,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                ],
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '글 종류',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            SegmentedButton<ItemType>(
              segments: const [
                ButtonSegment(
                  value: ItemType.found,
                  label: Text('습득(주웠어요)'),
                  icon: Icon(Icons.volunteer_activism_outlined),
                ),
                ButtonSegment(
                  value: ItemType.lost,
                  label: Text('분실(잃어버렸어요)'),
                  icon: Icon(Icons.search),
                ),
              ],
              selected: {_selectedType},
              onSelectionChanged: (newSelection) {
                setState(() {
                  _selectedType = newSelection.first;
                });
              },
              style: SegmentedButton.styleFrom(
                selectedBackgroundColor: AppColors.primary,
                selectedForegroundColor: Colors.white,
                backgroundColor: Colors.white,
                side: BorderSide(color: AppColors.line),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '물건 이름',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _titleController,
              decoration: InputDecoration(
                hintText: '예: 검은색 백팩, 아이폰 15 등',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '카테고리',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: AppColors.surface,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedCategory,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  items: kItemCategories
                      .map((c) => DropdownMenuItem(value: c, child: Text(c)))
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() => _selectedCategory = value);
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 24),
            const Text(
              '물건 세부 설명',
              style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _descriptionController,
              maxLines: 4,
              decoration: InputDecoration(
                hintText: '색상, 브랜드, 특징 등 자세히 적어주시면 찾는 데 도움이 돼요.',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 24),
            Text(
              _selectedType == ItemType.found ? '발견 장소' : '분실 장소',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const SizedBox(height: 10),
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: AppColors.line),
              ),
              child: DropdownButtonHideUnderline(
                child: DropdownButton<String>(
                  value: _selectedLocation,
                  isExpanded: true,
                  icon: const Icon(Icons.keyboard_arrow_down_rounded),
                  items: _locations
                      .map(
                        (loc) => DropdownMenuItem(value: loc, child: Text(loc)),
                      )
                      .toList(),
                  onChanged: (value) {
                    if (value != null) {
                      setState(() {
                        _selectedLocation = value;
                      });
                    }
                  },
                ),
              ),
            ),
            const SizedBox(height: 14),
            TextField(
              controller: _locationDetailController,
              decoration: InputDecoration(
                hintText: _selectedType == ItemType.found
                    ? '발견 장소 세부 설명 (예: 1층 북카페 창가 자리)'
                    : '분실 장소 세부 설명 (예: 1층 북카페 창가 자리)',
                filled: true,
                fillColor: Colors.white,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.line),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: AppColors.line),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: const BorderSide(
                    color: AppColors.primary,
                    width: 1.5,
                  ),
                ),
              ),
            ),
            const SizedBox(height: 36),
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
                  : Text(_isEditing ? '수정 완료' : '등록 완료'),
            ),
            const SizedBox(height: 12),
          ],
        ),
      ),
    );
  }
}

/// 글쓰기 화면의 선택된 사진 썸네일 + 제거 버튼.
class _ImagePickerTile extends StatelessWidget {
  final Widget child;
  final VoidCallback onRemove;

  const _ImagePickerTile({
    super.key,
    required this.child,
    required this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 88,
      height: 88,
      margin: const EdgeInsets.only(right: 10),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: AppColors.line),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          child,
          Positioned(
            top: 4,
            right: 4,
            child: GestureDetector(
              onTap: onRemove,
              child: Container(
                padding: const EdgeInsets.all(3),
                decoration: const BoxDecoration(
                  color: Colors.black54,
                  shape: BoxShape.circle,
                ),
                child: const Icon(Icons.close, color: Colors.white, size: 14),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 상세보기 상단의 사진 갤러리 (여러 장이면 스와이프 + 페이지 표시).
class _ImageGallery extends StatefulWidget {
  final List<String> imageUrls;

  const _ImageGallery({required this.imageUrls});

  @override
  State<_ImageGallery> createState() => _ImageGalleryState();
}

class _ImageGalleryState extends State<_ImageGallery> {
  final _controller = PageController();
  int _page = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(16),
      child: SizedBox(
        height: 210,
        child: Stack(
          children: [
            PageView.builder(
              controller: _controller,
              onPageChanged: (index) => setState(() => _page = index),
              itemCount: widget.imageUrls.length,
              itemBuilder: (context, index) => Image.network(
                widget.imageUrls[index],
                width: double.infinity,
                height: 210,
                fit: BoxFit.cover,
                errorBuilder: (context, error, stackTrace) => Container(
                  width: double.infinity,
                  height: 210,
                  color: AppColors.bg,
                  child: const Icon(
                    Icons.broken_image_outlined,
                    color: Color(0xFFC7CAD6),
                    size: 40,
                  ),
                ),
              ),
            ),
            if (widget.imageUrls.length > 1)
              Positioned(
                bottom: 10,
                right: 10,
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.55),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '${_page + 1}/${widget.imageUrls.length}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 11.5,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}

/// 화면 C: 상세 보기 BottomSheet
class ItemDetailSheet extends StatelessWidget {
  final LostFoundItem item;

  const ItemDetailSheet({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 16, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                Container(
                  width: 44,
                  height: 5,
                  decoration: BoxDecoration(
                    color: AppColors.line,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                if (FirebaseAuth.instance.currentUser?.uid != null &&
                    FirebaseAuth.instance.currentUser!.uid != item.authorUid)
                  Align(
                    alignment: Alignment.centerRight,
                    child: IconButton(
                      icon: const Icon(
                        Icons.flag_outlined,
                        size: 20,
                        color: AppColors.inkMuted,
                      ),
                      tooltip: '신고하기',
                      visualDensity: VisualDensity.compact,
                      onPressed: () => _reportItem(context),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 12),
            if (item.imageUrls.isNotEmpty) ...[
              _ImageGallery(imageUrls: item.imageUrls),
              const SizedBox(height: 18),
            ],
            Row(
              children: [
                _StatusBadge(type: item.type),
                if (item.resolved) ...[
                  const SizedBox(width: 6),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 9,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEDEEF3),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Text(
                      '거래완료',
                      style: TextStyle(
                        color: AppColors.inkMuted,
                        fontSize: 11,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                  ),
                ],
              ],
            ),
            const SizedBox(height: 12),
            Text(
              item.title,
              style: const TextStyle(
                fontSize: 22,
                fontWeight: FontWeight.w800,
                color: AppColors.ink,
                letterSpacing: -0.3,
              ),
            ),
            const SizedBox(height: 16),
            if (item.description.isNotEmpty) ...[
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: AppColors.bg,
                  borderRadius: BorderRadius.circular(14),
                ),
                child: Text(
                  item.description,
                  style: const TextStyle(
                    fontSize: 14,
                    height: 1.55,
                    color: AppColors.ink,
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
            _DetailRow(
              icon: Icons.place_outlined,
              label: item.type == ItemType.found ? '발견 장소' : '분실 장소',
              value: item.locationDetail.isEmpty
                  ? item.location
                  : '${item.location} (${item.locationDetail})',
            ),
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.label_outline,
              label: '글 종류',
              value: item.type == ItemType.found
                  ? '습득물 (주웠어요)'
                  : '분실물 (잃어버렸어요)',
            ),
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.category_outlined,
              label: '카테고리',
              value: item.category,
            ),
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.person_outline,
              label: '작성자',
              value: item.authorNickname,
            ),
            if (item.createdAt != null) ...[
              const SizedBox(height: 12),
              _DetailRow(
                icon: Icons.schedule_outlined,
                label: '등록일',
                value: relativeTime(item.createdAt),
              ),
            ],
            const SizedBox(height: 12),
            _DetailRow(
              icon: Icons.visibility_outlined,
              label: '조회수',
              value: '${item.viewCount}회',
            ),
            const SizedBox(height: 32),
            Builder(
              builder: (context) {
                final currentUid = FirebaseAuth.instance.currentUser?.uid;
                final isOwner =
                    currentUid == item.authorUid && item.authorUid.isNotEmpty;

                if (!isOwner) {
                  return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('blocks')
                        .doc(currentUid ?? '_')
                        .snapshots(),
                    builder: (context, snapshot) {
                      final blockedUsers = Map<String, dynamic>.from(
                        snapshot.data?.data()?['blockedUsers'] as Map? ?? {},
                      );
                      final hasBlocked = blockedUsers.containsKey(
                        item.authorUid,
                      );

                      if (hasBlocked) {
                        return Container(
                          width: double.infinity,
                          padding: const EdgeInsets.symmetric(vertical: 14),
                          decoration: BoxDecoration(
                            color: Colors.grey[200],
                            borderRadius: BorderRadius.circular(12),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '차단한 사용자입니다',
                            style: TextStyle(color: Colors.grey[700]),
                          ),
                        );
                      }

                      return SizedBox(
                        width: double.infinity,
                        height: 52,
                        child: ElevatedButton.icon(
                          onPressed: () => _startChat(context),
                          icon: const Icon(Icons.chat_bubble_outline),
                          label: const Text(
                            '채팅하기',
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: AppColors.primary,
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }

                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (!item.resolved)
                      SizedBox(
                        height: 48,
                        child: OutlinedButton.icon(
                          onPressed: () => _markResolved(context),
                          icon: const Icon(Icons.check_circle_outline),
                          label: const Text('거래완료로 표시'),
                          style: OutlinedButton.styleFrom(
                            foregroundColor: AppColors.primary,
                            side: const BorderSide(color: AppColors.primary),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                            ),
                          ),
                        ),
                      ),
                    const SizedBox(height: 12),
                    Row(
                      children: [
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () => _editItem(context),
                              icon: const Icon(Icons.edit_outlined),
                              label: const Text('수정'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: Colors.black87,
                                side: BorderSide(color: AppColors.line),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 12),
                        Expanded(
                          child: SizedBox(
                            height: 48,
                            child: OutlinedButton.icon(
                              onPressed: () => _confirmDelete(context),
                              icon: const Icon(Icons.delete_outline),
                              label: const Text('삭제'),
                              style: OutlinedButton.styleFrom(
                                foregroundColor: AppColors.danger,
                                side: const BorderSide(color: AppColors.danger),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(12),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                );
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _reportItem(BuildContext context) async {
    const reasons = ['부적절한 내용', '스팸/광고', '사기 의심', '기타'];
    String selectedReason = reasons.first;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              title: const Text('게시글 신고하기'),
              content: RadioGroup<String>(
                groupValue: selectedReason,
                onChanged: (value) {
                  setDialogState(() => selectedReason = value!);
                },
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: reasons
                      .map(
                        (reason) => RadioListTile<String>(
                          contentPadding: EdgeInsets.zero,
                          title: Text(reason),
                          value: reason,
                        ),
                      )
                      .toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(false),
                  child: const Text('취소'),
                ),
                TextButton(
                  onPressed: () => Navigator.of(dialogContext).pop(true),
                  child: const Text('신고'),
                ),
              ],
            );
          },
        );
      },
    );

    if (confirmed != true || !context.mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    try {
      final reportRef = FirebaseFirestore.instance
          .collection('reports')
          .doc('${item.id}_$myUid');
      final itemRef = itemsCollection.doc(item.id);

      // 트랜잭션으로 처리해 "이번 신고가 자동 숨김 기준을 막 넘겼는지"를
      // 정확히 판단하고, 그 경우에만 작성자에게 알림을 한 번 보낸다.
      await FirebaseFirestore.instance.runTransaction((transaction) async {
        final itemSnap = await transaction.get(itemRef);
        final currentCount =
            (itemSnap.data()?['reportCount'] as num?)?.toInt() ?? 0;

        transaction.set(reportRef, {
          'itemId': item.id,
          'reporterUid': myUid,
          'reason': selectedReason,
          'createdAt': FieldValue.serverTimestamp(),
        });
        transaction.update(itemRef, {'reportCount': FieldValue.increment(1)});

        if (currentCount < kReportThreshold &&
            currentCount + 1 >= kReportThreshold) {
          transaction.set(
            FirebaseFirestore.instance.collection('notifications').doc(),
            {
              'recipientUid': item.authorUid,
              'senderUid': myUid,
              'type': 'item_hidden',
              'itemId': item.id,
              'itemTitle': item.title,
              'read': false,
              'createdAt': FieldValue.serverTimestamp(),
            },
          );
        }
      });
      messenger.showSnackBar(const SnackBar(content: Text('신고가 접수되었습니다.')));
    } on FirebaseException catch (e) {
      final message = e.code == 'permission-denied'
          ? '이미 신고한 게시글입니다.'
          : '신고를 접수하지 못했습니다: ${e.message}';
      messenger.showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _markResolved(BuildContext context) async {
    final navigator = Navigator.of(context);
    try {
      await itemsCollection.doc(item.id).update({'resolved': true});

      // 이 글로 진행 중이던 모든 채팅의 거래완료 상태도 함께 맞춰서,
      // "상대방 확인 대기 중" 배너가 채팅방에 그대로 남아있지 않도록 한다.
      final relatedChats = await FirebaseFirestore.instance
          .collection('chats')
          .where('itemId', isEqualTo: item.id)
          .get();
      if (relatedChats.docs.isNotEmpty) {
        final batch = FirebaseFirestore.instance.batch();
        for (final chatDoc in relatedChats.docs) {
          batch.set(chatDoc.reference, {
            'resolutionStatus': 'done',
          }, SetOptions(merge: true));
        }
        await batch.commit();
      }

      navigator.pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('처리하지 못했습니다: $e')));
      }
    }
  }

  void _editItem(BuildContext context) {
    final navigator = Navigator.of(context);
    navigator.pop();
    navigator.push(
      MaterialPageRoute(
        builder: (context) => RegisterItemScreen(editingItem: item),
      ),
    );
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('게시글 삭제'),
        content: const Text('이 게시글을 삭제하시겠습니까? 삭제 후에는 되돌릴 수 없습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('삭제', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    if (!context.mounted) return;

    final navigator = Navigator.of(context);
    try {
      await itemsCollection.doc(item.id).delete();
      navigator.pop();
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('삭제하지 못했습니다: $e')));
      }
    }
  }

  Future<void> _startChat(BuildContext context) async {
    final currentUser = FirebaseAuth.instance.currentUser;
    if (currentUser == null || item.id == null) return;

    if (item.authorUid == currentUser.uid) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('본인이 등록한 게시글입니다.')));
      return;
    }

    final uids = [currentUser.uid, item.authorUid]..sort();
    final chatId = '${item.id}_${uids.join('_')}';
    final chatRef = FirebaseFirestore.instance.collection('chats').doc(chatId);

    final navigator = Navigator.of(context);

    try {
      final snap = await chatRef.get();
      if (!snap.exists) {
        await chatRef.set({
          'participants': uids,
          'participantNicknames': {
            currentUser.uid: currentUser.displayName ?? '익명',
            item.authorUid: item.authorNickname,
          },
          'itemId': item.id,
          'itemTitle': item.title,
          'itemAuthorUid': item.authorUid,
          'createdAt': FieldValue.serverTimestamp(),
          'lastMessage': '',
          'lastMessageAt': FieldValue.serverTimestamp(),
          'lastReadAt': {currentUser.uid: FieldValue.serverTimestamp()},
          'resolutionStatus': 'none',
        });

        await FirebaseFirestore.instance.collection('notifications').add({
          'recipientUid': item.authorUid,
          'senderUid': currentUser.uid,
          'senderNickname': currentUser.displayName ?? '익명',
          'type': 'chat_started',
          'itemId': item.id,
          'itemTitle': item.title,
          'chatId': chatId,
          'read': false,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('채팅을 시작하지 못했습니다: $e')));
      }
      return;
    }

    navigator.pop();
    navigator.push(
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          chatId: chatId,
          itemTitle: item.title,
          otherNickname: item.authorNickname,
          otherUid: item.authorUid,
        ),
      ),
    );
  }
}

class _DetailRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final String value;

  const _DetailRow({
    required this.icon,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.inkMuted),
        const SizedBox(width: 8),
        SizedBox(
          width: 68,
          child: Text(
            label,
            style: const TextStyle(fontSize: 13.5, color: AppColors.inkMuted),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.w600,
              color: AppColors.ink,
            ),
          ),
        ),
      ],
    );
  }
}

/// 닉네임 첫 글자를 담은 그라데이션 원형 아바타.
class UserAvatar extends StatelessWidget {
  final String nickname;
  final double size;

  const UserAvatar({super.key, required this.nickname, this.size = 44});

  @override
  Widget build(BuildContext context) {
    final trimmed = nickname.trim();
    final letter = trimmed.isNotEmpty ? trimmed.characters.first : '?';
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        gradient: kBrandGradient,
        shape: BoxShape.circle,
      ),
      child: Text(
        letter,
        style: TextStyle(
          color: Colors.white,
          fontSize: size * 0.42,
          fontWeight: FontWeight.w800,
        ),
      ),
    );
  }
}

/// 화면: 내 채팅 목록
class ChatListScreen extends StatelessWidget {
  /// null이면 아직 로딩 중, 빈 리스트면 채팅이 없는 상태.
  /// MainNavScreen이 안읽음 배지용으로 구독 중인 스트림을 그대로 넘겨받아
  /// 같은 chats 쿼리를 두 번 구독하지 않도록 한다.
  final List<QueryDocumentSnapshot<Map<String, dynamic>>>? docs;
  final bool hasError;

  const ChatListScreen({super.key, this.docs, this.hasError = false});

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('채팅', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: Builder(
        builder: (context) {
          if (hasError) {
            return const _FeedMessage(
              icon: Icons.error_outline_rounded,
              text: '채팅 목록을 불러오지 못했습니다.',
            );
          }
          if (docs == null) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final visibleDocs =
              docs!.where((doc) {
                final data = doc.data();
                final clearedAt = Map<String, dynamic>.from(
                  data['clearedAt'] as Map? ?? {},
                );
                final myClearedAt = clearedAt[uid] as Timestamp?;
                if (myClearedAt == null) return true;
                final lastMessageAt = data['lastMessageAt'] as Timestamp?;
                return lastMessageAt != null &&
                    lastMessageAt.compareTo(myClearedAt) > 0;
              }).toList()..sort((a, b) {
                final aAt = a.data()['lastMessageAt'] as Timestamp?;
                final bAt = b.data()['lastMessageAt'] as Timestamp?;
                if (aAt == null || bAt == null) return 0;
                return bAt.compareTo(aAt);
              });

          if (visibleDocs.isEmpty) {
            return const _FeedMessage(
              icon: Icons.chat_bubble_outline_rounded,
              text: '진행 중인 채팅이 없어요.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: visibleDocs.length,
            itemBuilder: (context, index) {
              final data = visibleDocs[index].data();
              final participants = List<String>.from(
                data['participants'] as List? ?? [],
              );
              final otherUid = participants.firstWhere(
                (u) => u != uid,
                orElse: () => '',
              );
              final nicknames = Map<String, dynamic>.from(
                data['participantNicknames'] as Map? ?? {},
              );
              final otherNickname = nicknames[otherUid] as String? ?? '알 수 없음';
              final lastMessage = data['lastMessage'] as String? ?? '';
              final itemTitle = data['itemTitle'] as String? ?? '';

              final lastReadAt = Map<String, dynamic>.from(
                data['lastReadAt'] as Map? ?? {},
              );
              final myLastRead = lastReadAt[uid] as Timestamp?;
              final lastMessageAt = data['lastMessageAt'] as Timestamp?;
              final isUnread =
                  lastMessage.isNotEmpty &&
                  lastMessageAt != null &&
                  (myLastRead == null ||
                      lastMessageAt.compareTo(myLastRead) > 0);

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(
                    color: isUnread ? AppColors.primary : AppColors.line,
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 8,
                  ),
                  leading: UserAvatar(nickname: otherNickname),
                  title: Text(
                    otherNickname,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      color: AppColors.ink,
                    ),
                  ),
                  subtitle: Text(
                    lastMessage.isNotEmpty ? lastMessage : itemTitle,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontWeight: isUnread
                          ? FontWeight.w700
                          : FontWeight.normal,
                      color: isUnread ? AppColors.ink : AppColors.inkMuted,
                    ),
                  ),
                  trailing: isUnread
                      ? Container(
                          width: 10,
                          height: 10,
                          decoration: const BoxDecoration(
                            color: AppColors.primary,
                            shape: BoxShape.circle,
                          ),
                        )
                      : null,
                  onTap: () => Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => ChatScreen(
                        chatId: visibleDocs[index].id,
                        itemTitle: itemTitle,
                        otherNickname: otherNickname,
                        otherUid: otherUid,
                      ),
                    ),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 화면: 1:1 채팅
class ChatScreen extends StatefulWidget {
  final String chatId;
  final String itemTitle;
  final String otherNickname;
  final String otherUid;

  const ChatScreen({
    super.key,
    required this.chatId,
    required this.itemTitle,
    required this.otherNickname,
    required this.otherUid,
  });

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSendingImage = false;
  late final Future<Timestamp?> _myClearedAtFuture = _loadMyClearedAt();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _messagesSub;

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages');

  @override
  void initState() {
    super.initState();
    _markAsRead();
    // 채팅방을 켜둔 채로 새 메시지가 도착해도 안읽음 처리되지 않도록,
    // 메시지가 갱신될 때마다 읽음 시각을 함께 갱신한다. 전체 기록을 다시
    // 읽지 않도록 가장 최근 문서 1개만 구독한다.
    _messagesSub = _messagesRef
        .orderBy('createdAt', descending: true)
        .limit(1)
        .snapshots()
        .listen((_) {
          _markAsRead();
        });
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.jumpTo(_scrollController.position.maxScrollExtent);
      }
    });
  }

  /// 카카오톡 방식 나가기: 내가 마지막으로 나간(비운) 시점 이전 메시지는
  /// 내 화면에서만 숨긴다. 상대방은 이 값과 무관하게 전체 대화를 그대로 본다.
  Future<Timestamp?> _loadMyClearedAt() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return null;
    final doc = await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .get();
    final clearedAt = Map<String, dynamic>.from(
      doc.data()?['clearedAt'] as Map? ?? {},
    );
    return clearedAt[myUid] as Timestamp?;
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    _messagesSub?.cancel();
    super.dispose();
  }

  Future<void> _markAsRead() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'lastReadAt.$myUid': FieldValue.serverTimestamp()});
    } catch (_) {
      // 읽음 처리 실패는 대화 자체를 막을 정도로 치명적이지 않으므로 조용히 무시한다.
    }
  }

  Future<void> _send() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    try {
      await _messagesRef.add({
        'senderUid': user.uid,
        'type': 'text',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('[메시지 저장 실패] $e')));
      }
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
            'lastMessage': text,
            'lastMessageAt': FieldValue.serverTimestamp(),
            'lastReadAt.${user.uid}': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('[채팅방 갱신 실패] $e')));
      }
    }
  }

  Future<void> _sendImage() async {
    final picked = await ImagePicker().pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
      maxWidth: 1600,
    );
    if (picked == null) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    setState(() => _isSendingImage = true);
    try {
      final url = await uploadImageToCloudinary(picked);
      await _messagesRef.add({
        'senderUid': user.uid,
        'type': 'image',
        'imageUrl': url,
        'createdAt': FieldValue.serverTimestamp(),
      });
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
            'lastMessage': '사진을 보냈습니다',
            'lastMessageAt': FieldValue.serverTimestamp(),
            'lastReadAt.${user.uid}': FieldValue.serverTimestamp(),
          });
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('사진 전송에 실패했습니다: $e')));
      }
    } finally {
      if (mounted) setState(() => _isSendingImage = false);
    }
  }

  void _openImageViewer(String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (dialogContext) => GestureDetector(
        onTap: () => Navigator.pop(dialogContext),
        child: Scaffold(
          backgroundColor: Colors.black,
          body: Center(child: InteractiveViewer(child: Image.network(url))),
        ),
      ),
    );
  }

  Future<void> _leaveChat() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('채팅방 나가기'),
        content: const Text(
          '나가면 지금까지의 대화 내용이 내 화면에서만 사라집니다.\n'
          '상대방의 채팅방에는 아무 변화가 없으며, 나간 사실도 알 수 없습니다.\n'
          '이후 누군가 메시지를 보내면 그 시점부터 새 채팅방처럼 다시 나타납니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('나가기', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || !mounted) return;

    final navigator = Navigator.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'clearedAt.$myUid': FieldValue.serverTimestamp()});
      navigator.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('나가기에 실패했습니다: $e')));
      }
    }
  }

  Future<void> _requestResolution() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    final chatDoc = await FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .get();
    final itemAuthorUid = chatDoc.data()?['itemAuthorUid'] as String?;
    if (itemAuthorUid != myUid) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('게시글 작성자만 거래완료를 요청할 수 있어요.')),
        );
      }
      return;
    }

    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).set(
      {'resolutionStatus': 'pending'},
      SetOptions(merge: true),
    );

    if (mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('상대방에게 거래완료 확인을 요청했어요.')));
    }
  }

  Future<void> _confirmResolution() async {
    await FirebaseFirestore.instance.collection('chats').doc(widget.chatId).set(
      {'resolutionStatus': 'confirmed'},
      SetOptions(merge: true),
    );
  }

  Future<void> _finalizeResolution(String itemId) async {
    try {
      await itemsCollection.doc(itemId).update({'resolved': true});

      // 같은 글로 진행 중이던 다른 채팅이 있다면 그 쪽의 배너도 함께 정리한다
      // (현재 채팅방도 itemId가 같으므로 이 목록에 포함된다).
      final relatedChats = await FirebaseFirestore.instance
          .collection('chats')
          .where('itemId', isEqualTo: itemId)
          .get();
      final batch = FirebaseFirestore.instance.batch();
      for (final chatDoc in relatedChats.docs) {
        batch.set(chatDoc.reference, {
          'resolutionStatus': 'done',
        }, SetOptions(merge: true));
      }
      await batch.commit();

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('거래완료로 처리했어요.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('처리에 실패했습니다: $e')));
      }
    }
  }

  Future<void> _revealRealName() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('실명 공개'),
        content: const Text(
          '상대방에게 가입 시 등록한 실명을 공개합니다.\n'
          '물품 인수·인계 등 신원 확인이 필요할 때만 사용해주세요.\n'
          '공개한 실명은 취소할 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('공개하기'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;

    try {
      final privateDoc = await FirebaseFirestore.instance
          .collection('userPrivate')
          .doc(myUid)
          .get();
      final realName = privateDoc.data()?['realName'] as String? ?? '';
      if (realName.isEmpty) {
        if (mounted) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(const SnackBar(content: Text('등록된 실명 정보가 없습니다.')));
        }
        return;
      }

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'revealedRealNames.$myUid': realName});

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('실명을 공개했습니다.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('실명 공개에 실패했습니다: $e')));
      }
    }
  }

  Future<void> _blockUser() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text('사용자 차단'),
        content: Text(
          '${widget.otherNickname}님을 차단하시겠습니까?\n차단하면 이 사용자는 더 이상 채팅을 걸거나 메시지를 보낼 수 없습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('취소'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('차단', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || !mounted) return;

    final navigator = Navigator.of(context);
    final messenger = ScaffoldMessenger.of(context);
    try {
      await FirebaseFirestore.instance.collection('blocks').doc(myUid).set({
        'blockedUsers': {widget.otherUid: widget.otherNickname},
      }, SetOptions(merge: true));
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'clearedAt.$myUid': FieldValue.serverTimestamp()});
      messenger.showSnackBar(
        SnackBar(content: Text('${widget.otherNickname}님을 차단했습니다.')),
      );
      navigator.pop();
    } catch (e) {
      messenger.showSnackBar(SnackBar(content: Text('차단에 실패했습니다: $e')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        backgroundColor: AppColors.bg,
        elevation: 0,
        titleSpacing: 4,
        title: Row(
          children: [
            UserAvatar(nickname: widget.otherNickname, size: 34),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    widget.otherNickname,
                    style: const TextStyle(
                      fontWeight: FontWeight.w700,
                      fontSize: 15,
                      color: AppColors.ink,
                    ),
                  ),
                  Text(
                    widget.itemTitle,
                    style: const TextStyle(
                      fontSize: 12,
                      color: AppColors.inkMuted,
                    ),
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          PopupMenuButton<String>(
            icon: const Icon(Icons.more_vert),
            onSelected: (value) {
              if (value == 'resolve') _requestResolution();
              if (value == 'reveal') _revealRealName();
              if (value == 'leave') _leaveChat();
              if (value == 'block') _blockUser();
            },
            itemBuilder: (context) => const [
              PopupMenuItem(value: 'resolve', child: Text('거래완료 확인 요청하기')),
              PopupMenuItem(value: 'reveal', child: Text('실명 공개하기')),
              PopupMenuItem(value: 'leave', child: Text('채팅방 나가기')),
              PopupMenuItem(
                value: 'block',
                child: Text(
                  '사용자 차단',
                  style: TextStyle(color: AppColors.danger),
                ),
              ),
            ],
          ),
        ],
      ),
      body: Column(
        children: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('chats')
                .doc(widget.chatId)
                .snapshots(),
            builder: (context, snapshot) {
              final data = snapshot.data?.data();
              if (data == null) return const SizedBox.shrink();

              final myUid = FirebaseAuth.instance.currentUser?.uid;
              final itemAuthorUid = data['itemAuthorUid'] as String?;
              final isOwner = myUid != null && myUid == itemAuthorUid;
              final itemId = data['itemId'] as String?;
              final resolutionStatus =
                  data['resolutionStatus'] as String? ?? 'none';

              final revealed = Map<String, dynamic>.from(
                data['revealedRealNames'] as Map? ?? {},
              );
              final otherRealName =
                  revealed.entries
                          .firstWhere(
                            (entry) => entry.key != myUid,
                            orElse: () => const MapEntry('', null),
                          )
                          .value
                      as String?;

              final banners = <Widget>[];

              if (otherRealName != null && otherRealName.isNotEmpty) {
                banners.add(
                  _ChatBanner(
                    icon: Icons.verified_user_outlined,
                    text: '${widget.otherNickname}님이 실명을 공개했어요: $otherRealName',
                  ),
                );
              }

              if (resolutionStatus == 'pending') {
                banners.add(
                  isOwner
                      ? const _ChatBanner(
                          icon: Icons.hourglass_empty_rounded,
                          text: '상대방의 거래완료 확인을 기다리는 중이에요.',
                        )
                      : _ChatBanner(
                          icon: Icons.task_alt_outlined,
                          text: '${widget.otherNickname}님이 거래완료를 요청했어요.',
                          actionLabel: '확인',
                          onAction: _confirmResolution,
                        ),
                );
              } else if (resolutionStatus == 'confirmed' &&
                  isOwner &&
                  itemId != null) {
                banners.add(
                  _ChatBanner(
                    icon: Icons.check_circle_outline_rounded,
                    text: '상대방이 거래완료를 확인했어요.',
                    actionLabel: '완료 처리',
                    onAction: () => _finalizeResolution(itemId),
                  ),
                );
              }

              if (banners.isEmpty) return const SizedBox.shrink();
              return Column(children: banners);
            },
          ),
          Expanded(
            child: FutureBuilder<Timestamp?>(
              future: _myClearedAtFuture,
              builder: (context, clearedSnapshot) {
                if (clearedSnapshot.connectionState ==
                    ConnectionState.waiting) {
                  return const Center(
                    child: CircularProgressIndicator(color: AppColors.primary),
                  );
                }

                final myClearedAt = clearedSnapshot.data;
                Query<Map<String, dynamic>> query = _messagesRef.orderBy(
                  'createdAt',
                );
                if (myClearedAt != null) {
                  query = query.where('createdAt', isGreaterThan: myClearedAt);
                }

                return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
                  stream: query.snapshots(),
                  builder: (context, snapshot) {
                    if (snapshot.hasError) {
                      return const _FeedMessage(
                        icon: Icons.error_outline_rounded,
                        text: '메시지를 불러오지 못했습니다.',
                      );
                    }
                    if (!snapshot.hasData) {
                      return const Center(
                        child: CircularProgressIndicator(
                          color: AppColors.primary,
                        ),
                      );
                    }

                    final docs = snapshot.data!.docs;
                    if (docs.isEmpty) {
                      return const _FeedMessage(
                        icon: Icons.waving_hand_outlined,
                        text: '첫 메시지를 보내보세요!',
                      );
                    }

                    _scrollToBottom();
                    return ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(16),
                      itemCount: docs.length,
                      itemBuilder: (context, index) {
                        final data = docs[index].data();
                        final isMine = data['senderUid'] == myUid;
                        final isImage = data['type'] == 'image';

                        if (isImage) {
                          final imageUrl = data['imageUrl'] as String? ?? '';
                          return Align(
                            alignment: isMine
                                ? Alignment.centerRight
                                : Alignment.centerLeft,
                            child: GestureDetector(
                              onTap: () => _openImageViewer(imageUrl),
                              child: Container(
                                margin: const EdgeInsets.only(bottom: 8),
                                constraints: BoxConstraints(
                                  maxWidth:
                                      MediaQuery.of(context).size.width * 0.55,
                                ),
                                child: ClipRRect(
                                  borderRadius: BorderRadius.circular(16),
                                  child: Image.network(
                                    imageUrl,
                                    fit: BoxFit.cover,
                                    errorBuilder:
                                        (context, error, stackTrace) =>
                                            Container(
                                              width: 160,
                                              height: 160,
                                              color: AppColors.bg,
                                              child: const Icon(
                                                Icons.broken_image_outlined,
                                                color: Color(0xFFC7CAD6),
                                              ),
                                            ),
                                  ),
                                ),
                              ),
                            ),
                          );
                        }

                        return Align(
                          alignment: isMine
                              ? Alignment.centerRight
                              : Alignment.centerLeft,
                          child: Container(
                            margin: const EdgeInsets.only(bottom: 8),
                            padding: const EdgeInsets.symmetric(
                              horizontal: 14,
                              vertical: 10,
                            ),
                            constraints: BoxConstraints(
                              maxWidth: MediaQuery.of(context).size.width * 0.7,
                            ),
                            decoration: BoxDecoration(
                              color: isMine ? AppColors.primary : Colors.white,
                              borderRadius: BorderRadius.circular(16),
                              border: isMine
                                  ? null
                                  : Border.all(color: AppColors.line),
                            ),
                            child: Text(
                              data['text'] as String? ?? '',
                              style: TextStyle(
                                color: isMine ? Colors.white : AppColors.ink,
                              ),
                            ),
                          ),
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          SafeArea(
            top: false,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Row(
                children: [
                  IconButton(
                    onPressed: _isSendingImage ? null : _sendImage,
                    icon: _isSendingImage
                        ? const SizedBox(
                            width: 20,
                            height: 20,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.add_photo_alternate_outlined),
                    color: AppColors.inkMuted,
                  ),
                  Expanded(
                    child: TextField(
                      controller: _messageController,
                      decoration: InputDecoration(
                        hintText: '메시지 입력',
                        filled: true,
                        fillColor: Colors.white,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        border: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: AppColors.line),
                        ),
                        enabledBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: BorderSide(color: AppColors.line),
                        ),
                        focusedBorder: OutlineInputBorder(
                          borderRadius: BorderRadius.circular(24),
                          borderSide: const BorderSide(
                            color: AppColors.primary,
                            width: 1.5,
                          ),
                        ),
                      ),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 4),
                  IconButton(
                    onPressed: _send,
                    icon: const Icon(Icons.send_rounded),
                    color: AppColors.primary,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 채팅방 상단에 표시되는 안내 배너 (실명 공개, 거래완료 요청/확인 등).
class _ChatBanner extends StatelessWidget {
  final IconData icon;
  final String text;
  final String? actionLabel;
  final VoidCallback? onAction;

  const _ChatBanner({
    required this.icon,
    required this.text,
    this.actionLabel,
    this.onAction,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: AppColors.primary.withValues(alpha: 0.06),
      child: Row(
        children: [
          Icon(icon, size: 16, color: AppColors.primary),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              text,
              style: const TextStyle(
                fontSize: 12.5,
                color: AppColors.ink,
                fontWeight: FontWeight.w600,
              ),
            ),
          ),
          if (actionLabel != null)
            TextButton(
              onPressed: onAction,
              style: TextButton.styleFrom(
                padding: const EdgeInsets.symmetric(horizontal: 10),
                minimumSize: Size.zero,
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(actionLabel!),
            ),
        ],
      ),
    );
  }
}

/// 화면: 차단한 사용자 관리
class BlockedUsersScreen extends StatelessWidget {
  const BlockedUsersScreen({super.key});

  Future<void> _unblock(
    BuildContext context,
    String uid,
    String otherUid,
  ) async {
    try {
      await FirebaseFirestore.instance.collection('blocks').doc(uid).update({
        'blockedUsers.$otherUid': FieldValue.delete(),
      });
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('차단 해제에 실패했습니다: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text(
          '차단 관리',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('blocks')
            .doc(uid ?? '_')
            .snapshots(),
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final blockedUsers = Map<String, dynamic>.from(
            snapshot.data?.data()?['blockedUsers'] as Map? ?? {},
          );

          if (blockedUsers.isEmpty) {
            return const _FeedMessage(
              icon: Icons.block_outlined,
              text: '차단한 사용자가 없어요.',
            );
          }

          final entries = blockedUsers.entries.toList();
          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: entries.length,
            itemBuilder: (context, index) {
              final otherUid = entries[index].key;
              final nickname = entries[index].value as String? ?? '알 수 없음';
              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                color: AppColors.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: const BorderSide(color: AppColors.line),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  title: Text(
                    nickname,
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  trailing: TextButton(
                    onPressed: uid == null
                        ? null
                        : () => _unblock(context, uid, otherUid),
                    child: const Text('차단 해제'),
                  ),
                ),
              );
            },
          );
        },
      ),
    );
  }
}

/// 앱바의 알림 벨 아이콘. 읽지 않은 알림 개수를 배지로 표시한다.
class _NotificationBellButton extends StatelessWidget {
  const _NotificationBellButton();

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance
          .collection('notifications')
          .where('recipientUid', isEqualTo: uid)
          .where('read', isEqualTo: false)
          .snapshots(),
      builder: (context, snapshot) {
        final unreadCount = snapshot.data?.docs.length ?? 0;
        return IconButton(
          icon: Stack(
            clipBehavior: Clip.none,
            children: [
              const Icon(Icons.notifications_none_rounded),
              if (unreadCount > 0)
                Positioned(
                  right: -2,
                  top: -2,
                  child: Container(
                    padding: const EdgeInsets.all(3),
                    decoration: const BoxDecoration(
                      color: AppColors.danger,
                      shape: BoxShape.circle,
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 14,
                      minHeight: 14,
                    ),
                    child: Text(
                      unreadCount > 9 ? '9+' : '$unreadCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
            ],
          ),
          onPressed: () {
            Navigator.push(
              context,
              MaterialPageRoute(
                builder: (context) => const NotificationsScreen(),
              ),
            );
          },
        );
      },
    );
  }
}

/// 화면: 알림 목록
class NotificationsScreen extends StatelessWidget {
  const NotificationsScreen({super.key});

  Future<void> _openNotification(
    BuildContext context,
    QueryDocumentSnapshot<Map<String, dynamic>> doc,
  ) async {
    final data = doc.data();
    await doc.reference.update({'read': true});
    if (!context.mounted) return;
    final type = data['type'] as String? ?? 'chat_started';
    if (type != 'chat_started') return;
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) => ChatScreen(
          chatId: data['chatId'] as String? ?? '',
          itemTitle: data['itemTitle'] as String? ?? '',
          otherNickname: data['senderNickname'] as String? ?? '알 수 없음',
          otherUid: data['senderUid'] as String? ?? '',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final uid = FirebaseAuth.instance.currentUser?.uid;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(
        title: const Text('알림', style: TextStyle(fontWeight: FontWeight.bold)),
        backgroundColor: AppColors.bg,
        elevation: 0,
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: FirebaseFirestore.instance
            .collection('notifications')
            .where('recipientUid', isEqualTo: uid)
            .orderBy('createdAt', descending: true)
            .snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return const _FeedMessage(
              icon: Icons.error_outline_rounded,
              text: '알림을 불러오지 못했습니다.',
            );
          }
          if (!snapshot.hasData) {
            return const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            );
          }

          final docs = snapshot.data!.docs;
          if (docs.isEmpty) {
            return const _FeedMessage(
              icon: Icons.notifications_none_rounded,
              text: '알림이 없어요.',
            );
          }

          return ListView.builder(
            padding: const EdgeInsets.all(20),
            itemCount: docs.length,
            itemBuilder: (context, index) {
              final doc = docs[index];
              final data = doc.data();
              final read = data['read'] as bool? ?? false;
              final senderNickname =
                  data['senderNickname'] as String? ?? '알 수 없음';
              final itemTitle = data['itemTitle'] as String? ?? '';
              final type = data['type'] as String? ?? 'chat_started';
              final isHiddenNotice = type == 'item_hidden';

              return Card(
                margin: const EdgeInsets.only(bottom: 12),
                elevation: 0,
                color: read
                    ? Colors.white
                    : AppColors.primary.withValues(alpha: 0.05),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(
                    color: read
                        ? AppColors.line
                        : AppColors.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: ListTile(
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 4,
                  ),
                  leading: Icon(
                    isHiddenNotice
                        ? Icons.visibility_off_outlined
                        : Icons.chat_bubble_outline,
                    color: read
                        ? Colors.grey[400]
                        : (isHiddenNotice
                              ? AppColors.danger
                              : AppColors.primary),
                  ),
                  title: Text(
                    isHiddenNotice
                        ? "'$itemTitle' 게시글이 신고 누적으로 숨김 처리됐어요"
                        : '$senderNickname님이 채팅을 걸었어요',
                    style: TextStyle(
                      fontWeight: read ? FontWeight.normal : FontWeight.bold,
                    ),
                  ),
                  subtitle: isHiddenNotice
                      ? const Text(
                          '마이페이지 > 내 글에서 확인할 수 있어요',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        )
                      : Text(
                          itemTitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                  onTap: () => _openNotification(context, doc),
                ),
              );
            },
          );
        },
      ),
    );
  }
}
