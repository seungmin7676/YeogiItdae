import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;

import '../models/lost_found_item.dart';
import '../services/backend_exception.dart';
import '../theme/app_theme.dart';
import 'blocked_users_screen.dart';

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
                            await FirebaseFirestore.instance
                                .collection('userPublicProfiles')
                                .doc(user.uid)
                                .set({'nickname': newNickname});
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
      final myNotifications = await FirebaseFirestore.instance
          .collection('notifications')
          .where('recipientUid', isEqualTo: user.uid)
          .get();

      // chats/messages는 상대방과 공유하는 문서라 여기서 지우지 않는다.
      // 지우면 상대방 화면에서도 대화 기록 전체가 함께 사라져버린다.
      final refsToDelete = <DocumentReference>[
        ...myItems.docs.map((d) => d.reference),
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
        title: const Text('마이페이지'),
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
        borderRadius: BorderRadius.circular(16),
        boxShadow: kSoftShadow,
      ),
      child: Material(
        color: AppColors.surface,
        borderRadius: BorderRadius.circular(16),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
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
      ),
    );
  }
}
