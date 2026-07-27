import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import '../models/lost_found_item.dart';
import '../services/admin.dart';
import '../services/backend_exception.dart';
import '../services/cloudinary_service.dart';
import '../services/error_messages.dart';
import '../services/push_notifications.dart';
import '../services/push_sender.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/count_badge.dart';
import '../widgets/user_avatar.dart';
import 'admin_bug_reports_screen.dart';
import 'admin_reports_screen.dart';
import 'blocked_users_screen.dart';
import 'notification_settings_screen.dart';
import 'saved_items_screen.dart';
import 'saved_searches_screen.dart';

/// 화면: 마이페이지 (닉네임 관리, 차단 관리, 로그아웃, 회원 탈퇴)
class ProfileScreen extends StatefulWidget {
  const ProfileScreen({super.key});

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _isDeleting = false;
  bool _isChangingPhoto = false;

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

  Future<void> _changePhoto(bool hasPhoto) async {
    if (_isChangingPhoto) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    final action = await showModalBottomSheet<String>(
      context: context,
      backgroundColor: AppColors.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(kRadiusXl)),
      ),
      builder: (context) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.photo_camera_outlined),
              title: const Text('카메라로 촬영'),
              onTap: () => Navigator.pop(context, 'camera'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_outlined),
              title: const Text('갤러리에서 선택'),
              onTap: () => Navigator.pop(context, 'gallery'),
            ),
            if (hasPhoto)
              ListTile(
                leading: const Icon(
                  Icons.person_remove_outlined,
                  color: AppColors.danger,
                ),
                title: const Text(
                  '기본 이미지로 변경',
                  style: TextStyle(color: AppColors.danger),
                ),
                onTap: () => Navigator.pop(context, 'remove'),
              ),
          ],
        ),
      ),
    );
    if (action == null || !mounted) return;
    setState(() => _isChangingPhoto = true);

    final ref = FirebaseFirestore.instance
        .collection('userPublicProfiles')
        .doc(myUid);

    try {
      if (action == 'remove') {
        try {
          await ref.set({'photoUrl': ''}, SetOptions(merge: true));
        } catch (e) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('사진 삭제에 실패했습니다: ${friendlyErrorMessage(e)}'),
              ),
            );
          }
        }
        return;
      }

      final picked = await ImagePicker().pickImage(
        source: action == 'camera' ? ImageSource.camera : ImageSource.gallery,
        imageQuality: 80,
        maxWidth: 800,
      );
      if (picked == null || !mounted) return;

      try {
        final url = await uploadImageToCloudinary(picked);
        await ref.set({'photoUrl': url}, SetOptions(merge: true));
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('사진 업로드에 실패했습니다: ${friendlyErrorMessage(e)}'),
            ),
          );
        }
      }
    } finally {
      if (mounted) setState(() => _isChangingPhoto = false);
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
                borderRadius: BorderRadius.circular(kRadiusMd),
              ),
              title: const Text('닉네임 변경'),
              content: Form(
                key: formKey,
                child: TextFormField(
                  controller: nicknameController,
                  autofocus: true,
                  maxLength: 12,
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
                                SnackBar(
                                  content: Text(
                                    '변경에 실패했습니다: ${friendlyErrorMessage(e)}',
                                  ),
                                ),
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
    nicknameController.dispose();
  }

  Future<void> _confirmLogout() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '로그아웃',
      content: '정말 로그아웃하시겠습니까?',
      confirmLabel: '로그아웃',
      danger: true,
    );
    if (confirmed) {
      // signOut 이전에 이 기기 토큰을 지워야, 로그아웃 후 규칙상 쓰기가 막히기
      // 전에 정리가 끝난다(안 지우면 이 기기로 이전 계정 알림이 갈 수 있다).
      await PushNotifications.unregisterToken();
      await FirebaseAuth.instance.signOut();
    }
  }

  Future<void> _reportBug() async {
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    final controller = TextEditingController();
    final formKey = GlobalKey<FormState>();
    bool isSaving = false;

    await showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return StatefulBuilder(
          builder: (dialogContext, setDialogState) {
            return AlertDialog(
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(kRadiusMd),
              ),
              title: const Text('버그 신고'),
              content: Form(
                key: formKey,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      '불편한 점이나 오류를 알려주시면 개선에 큰 도움이 돼요.',
                      style: TextStyle(fontSize: 13, color: AppColors.inkMuted),
                    ),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: controller,
                      autofocus: true,
                      maxLength: 1000,
                      maxLines: 5,
                      minLines: 3,
                      textInputAction: TextInputAction.newline,
                      validator: (value) => (value?.trim().isEmpty ?? true)
                          ? '내용을 입력해주세요.'
                          : null,
                      decoration: const InputDecoration(
                        hintText: '어떤 상황에서 무엇이 문제였는지 적어주세요.',
                        alignLabelWithHint: true,
                      ),
                    ),
                  ],
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
                          final messenger = ScaffoldMessenger.of(context);
                          try {
                            await FirebaseFirestore.instance
                                .collection('bugReports')
                                .add({
                                  'reporterUid': user.uid,
                                  'reporterEmail': user.email ?? '',
                                  'reporterNickname': user.displayName ?? '',
                                  'content': controller.text.trim(),
                                  'createdAt': FieldValue.serverTimestamp(),
                                });
                            // 관리자에게 새 버그 신고 접수 푸시.
                            sendPush(
                              type: 'bug_report',
                              title: '새 버그 신고',
                              body: controller.text.trim(),
                            );
                            if (dialogContext.mounted) {
                              Navigator.pop(dialogContext);
                            }
                            messenger.showSnackBar(
                              const SnackBar(
                                content: Text('소중한 의견 감사합니다. 신고가 접수됐어요.'),
                              ),
                            );
                          } catch (e) {
                            setDialogState(() => isSaving = false);
                            if (dialogContext.mounted) {
                              ScaffoldMessenger.of(dialogContext).showSnackBar(
                                SnackBar(
                                  content: Text(
                                    '접수에 실패했습니다: ${friendlyErrorMessage(e)}',
                                  ),
                                ),
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
                      : const Text('보내기'),
                ),
              ],
            );
          },
        );
      },
    );
    controller.dispose();
  }

  Future<void> _deleteAccount() async {
    final passwordController = TextEditingController();
    final formKey = GlobalKey<FormState>();

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusMd),
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
                HapticFeedback.mediumImpact();
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

    final password = passwordController.text;
    passwordController.dispose();
    if (confirmed != true) return;

    final user = FirebaseAuth.instance.currentUser;
    if (user == null || user.email == null) return;

    setState(() => _isDeleting = true);

    try {
      final credential = EmailAuthProvider.credential(
        email: user.email!,
        password: password,
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
      await FirebaseFirestore.instance
          .collection('bookmarks')
          .doc(user.uid)
          .delete();
      await FirebaseFirestore.instance
          .collection('userPublicProfiles')
          .doc(user.uid)
          .delete();
      await FirebaseFirestore.instance
          .collection('savedSearches')
          .doc(user.uid)
          .delete();
      await FirebaseFirestore.instance
          .collection('fcmTokens')
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('탈퇴 처리 중 오류가 발생했습니다: ${friendlyErrorMessage(e)}'),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final user = FirebaseAuth.instance.currentUser;
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('마이페이지')),
      body: _isDeleting
          ? const Center(
              child: CircularProgressIndicator(color: AppColors.primary),
            )
          : ListView(
              padding: const EdgeInsets.fromLTRB(
                kPagePadding,
                8,
                kPagePadding,
                32,
              ),
              children: [
                // 프로필 헤더 — 카드 없이 여백과 타이포로만 구성한 플랫 헤더.
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 20),
                  child: Row(
                    children: [
                      StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                        stream: FirebaseFirestore.instance
                            .collection('userPublicProfiles')
                            .doc(user?.uid ?? '_')
                            .snapshots(),
                        builder: (context, snapshot) {
                          final photoUrl =
                              snapshot.data?.data()?['photoUrl'] as String?;
                          return GestureDetector(
                            onTap: _isChangingPhoto
                                ? null
                                : () => _changePhoto(
                                    photoUrl != null && photoUrl.isNotEmpty,
                                  ),
                            child: Stack(
                              clipBehavior: Clip.none,
                              children: [
                                Opacity(
                                  opacity: _isChangingPhoto ? 0.5 : 1,
                                  child: UserAvatar(
                                    nickname: user?.displayName ?? '익명',
                                    photoUrl: photoUrl,
                                    size: 64,
                                  ),
                                ),
                                if (_isChangingPhoto)
                                  const Positioned.fill(
                                    child: Center(
                                      child: SizedBox(
                                        width: 22,
                                        height: 22,
                                        child: CircularProgressIndicator(
                                          strokeWidth: 2.5,
                                          color: AppColors.primary,
                                        ),
                                      ),
                                    ),
                                  ),
                                Positioned(
                                  right: -2,
                                  bottom: -2,
                                  child: Container(
                                    padding: const EdgeInsets.all(4),
                                    decoration: const BoxDecoration(
                                      color: AppColors.ink,
                                      shape: BoxShape.circle,
                                      border: Border.fromBorderSide(
                                        BorderSide(
                                          color: AppColors.surface,
                                          width: 2,
                                        ),
                                      ),
                                    ),
                                    child: const Icon(
                                      Icons.camera_alt_rounded,
                                      color: Colors.white,
                                      size: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          );
                        },
                      ),
                      const SizedBox(width: 16),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              user?.displayName ?? '익명',
                              style: const TextStyle(
                                fontSize: 20,
                                fontWeight: FontWeight.w800,
                                letterSpacing: -0.4,
                                color: AppColors.ink,
                              ),
                            ),
                            const SizedBox(height: 3),
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
                const SectionLabel('보관함'),
                const SizedBox(height: 10),
                GroupSurface(
                  children: [
                    _ProfileMenuTile(
                      icon: Icons.bookmark_border_rounded,
                      label: '찜한 글',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SavedItemsScreen(),
                          ),
                        );
                      },
                    ),
                    _ProfileMenuTile(
                      icon: Icons.notifications_active_outlined,
                      label: '키워드 알림',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) => const SavedSearchesScreen(),
                          ),
                        );
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 24),
                const SectionLabel('설정'),
                const SizedBox(height: 10),
                GroupSurface(
                  children: [
                    _ProfileMenuTile(
                      icon: Icons.tune_rounded,
                      label: '알림 설정',
                      onTap: () {
                        Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (context) =>
                                const NotificationSettingsScreen(),
                          ),
                        );
                      },
                    ),
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
                    _ProfileMenuTile(
                      icon: Icons.bug_report_outlined,
                      label: '버그 신고',
                      onTap: _reportBug,
                    ),
                  ],
                ),
                if (isCurrentUserAdmin()) ...[
                  const SizedBox(height: 24),
                  const SectionLabel('관리자'),
                  const SizedBox(height: 10),
                  const GroupSurface(
                    children: [_AdminReportsTile(), _AdminBugReportsTile()],
                  ),
                ],
                const SizedBox(height: 24),
                const SectionLabel('계정'),
                const SizedBox(height: 10),
                GroupSurface(
                  children: [
                    _ProfileMenuTile(
                      icon: Icons.logout_rounded,
                      label: '로그아웃',
                      onTap: _confirmLogout,
                    ),
                    _ProfileMenuTile(
                      icon: Icons.person_remove_outlined,
                      label: '회원 탈퇴',
                      labelColor: AppColors.danger,
                      onTap: _deleteAccount,
                    ),
                  ],
                ),
              ],
            ),
    );
  }
}

/// 관리자 전용 '신고 관리' 진입 타일. 미처리 신고 개수를 배지로 보여줘
/// 별도 알림 없이도 새 신고가 쌓인 것을 알 수 있게 한다.
class _AdminReportsTile extends StatelessWidget {
  const _AdminReportsTile();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('reports').snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return ListTile(
          leading: const Icon(Icons.flag_outlined, color: AppColors.inkMuted),
          title: const Text(
            '신고 관리',
            style: TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
              fontSize: 14.5,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (count > 0) ...[
                CountBadge(count: count),
                const SizedBox(width: 8),
              ],
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.inkFaint,
              ),
            ],
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const AdminReportsScreen()),
          ),
        );
      },
    );
  }
}

/// 관리자 전용 '버그 신고 관리' 진입 타일. 접수된 버그 신고 개수를 배지로
/// 보여준다.
class _AdminBugReportsTile extends StatelessWidget {
  const _AdminBugReportsTile();

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
      stream: FirebaseFirestore.instance.collection('bugReports').snapshots(),
      builder: (context, snapshot) {
        final count = snapshot.data?.docs.length ?? 0;
        return ListTile(
          leading: const Icon(
            Icons.bug_report_outlined,
            color: AppColors.inkMuted,
          ),
          title: const Text(
            '버그 신고 관리',
            style: TextStyle(
              color: AppColors.ink,
              fontWeight: FontWeight.w600,
              fontSize: 14.5,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (count > 0) ...[
                CountBadge(count: count),
                const SizedBox(width: 8),
              ],
              const Icon(
                Icons.chevron_right_rounded,
                color: AppColors.inkFaint,
              ),
            ],
          ),
          onTap: () => Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const AdminBugReportsScreen(),
            ),
          ),
        );
      },
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
    return ListTile(
      leading: Icon(icon, color: labelColor ?? AppColors.inkMuted),
      title: Text(
        label,
        style: TextStyle(
          color: color,
          fontWeight: FontWeight.w600,
          fontSize: 14.5,
        ),
      ),
      trailing: const Icon(
        Icons.chevron_right_rounded,
        color: AppColors.inkFaint,
      ),
      onTap: onTap,
    );
  }
}
