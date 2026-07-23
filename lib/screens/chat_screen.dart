import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/lost_found_item.dart';
import '../services/cloudinary_service.dart';
import '../services/error_messages.dart';
import '../services/image_save_service.dart';
import '../theme/app_theme.dart';
import '../widgets/app_user_data.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/feed_message.dart';
import '../widgets/image_source_sheet.dart';
import '../widgets/user_avatar.dart';

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

class _ChatScreenState extends State<ChatScreen> with WidgetsBindingObserver {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();
  bool _isSendingImage = false;
  late final Future<Timestamp?> _myClearedAtFuture = _loadMyClearedAt();
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _messagesSub;
  Timer? _typingTimer;
  bool _isTypingFlagSet = false;

  CollectionReference<Map<String, dynamic>> get _messagesRef =>
      FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .collection('messages');

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // 앱을 백그라운드로 보내면(홈으로 나가기, 다른 앱으로 전환 등) "입력
    // 중..."이 상대방 화면에 계속 남아있지 않도록 정리한다. 앱이 완전히
    // 강제 종료/크래시하는 경우까지는 클라이언트에서 막을 방법이 없다.
    if (state != AppLifecycleState.resumed) {
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (myUid != null) _clearTyping(myUid);
    }
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
    WidgetsBinding.instance.removeObserver(this);
    _messageController.dispose();
    _scrollController.dispose();
    _messagesSub?.cancel();
    _typingTimer?.cancel();
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid != null && _isTypingFlagSet) {
      FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'typing.$myUid': false})
          .catchError((_) {});
    }
    super.dispose();
  }

  /// 입력창에 글자가 있으면 상대방에게 "입력 중..."을 보여주고, 3초간 추가
  /// 입력이 없으면 자동으로 꺼진다(메시지를 안 보내고 나가도 계속 켜져
  /// 있지 않도록).
  void _onMessageChanged(String text) {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    if (text.isEmpty) {
      _clearTyping(myUid);
      return;
    }

    if (!_isTypingFlagSet) {
      _isTypingFlagSet = true;
      FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'typing.$myUid': true})
          .catchError((_) {});
    }
    _typingTimer?.cancel();
    _typingTimer = Timer(const Duration(seconds: 3), () => _clearTyping(myUid));
  }

  void _clearTyping(String myUid) {
    _typingTimer?.cancel();
    if (!_isTypingFlagSet) return;
    _isTypingFlagSet = false;
    FirebaseFirestore.instance
        .collection('chats')
        .doc(widget.chatId)
        .update({'typing.$myUid': false})
        .catchError((_) {});
  }

  Future<void> _markAsRead() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
            'lastReadAt.$myUid': FieldValue.serverTimestamp(),
            'unreadCount.$myUid': 0,
          });
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
      final batch = FirebaseFirestore.instance.batch();
      final chatRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId);
      batch.set(_messagesRef.doc(), {
        'senderUid': user.uid,
        'type': 'text',
        'text': text,
        'createdAt': FieldValue.serverTimestamp(),
      });
      batch.update(chatRef, {
        'lastMessage': text,
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastReadAt.${user.uid}': FieldValue.serverTimestamp(),
        'unreadCount.${widget.otherUid}': FieldValue.increment(1),
        'typing.${user.uid}': false,
      });
      await batch.commit();
      _typingTimer?.cancel();
      _isTypingFlagSet = false;
      _messageController.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('메시지 전송에 실패했습니다: ${friendlyErrorMessage(e)}')),
        );
      }
    }
  }

  // 등록 화면(RegisterItemScreen)의 첨부 제한과 동일하게, 한 번에 너무 많은
  // 사진을 골라 순차 업로드가 오래 걸리거나 실수로 대량 전송하는 걸 막는다.
  static const int _maxImagesPerSend = 5;

  Future<void> _sendImage() async {
    final source = await showImageSourceSheet(context);
    if (source == null) return;

    List<XFile> picked;
    if (source == ImageSource.camera) {
      final photo = await ImagePicker().pickImage(
        source: ImageSource.camera,
        imageQuality: 80,
        maxWidth: 1600,
      );
      picked = photo == null ? [] : [photo];
    } else {
      picked = await ImagePicker().pickMultiImage(
        imageQuality: 80,
        maxWidth: 1600,
      );
    }
    if (picked.isEmpty || !mounted) return;
    final user = FirebaseAuth.instance.currentUser;
    if (user == null) return;

    if (picked.length > _maxImagesPerSend) {
      final excess = picked.length - _maxImagesPerSend;
      picked = picked.take(_maxImagesPerSend).toList();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '사진은 한 번에 최대 $_maxImagesPerSend장까지 보낼 수 있어 $excess장은 제외됐어요.',
          ),
        ),
      );
    }

    setState(() => _isSendingImage = true);
    try {
      // Cloudinary 업로드는 배치 트랜잭션 대상이 아니라 순서대로 먼저
      // 끝내둔 다음, 메시지 기록과 채팅방 메타데이터 갱신만 한 번에 묶는다.
      final urls = <String>[];
      for (final file in picked) {
        urls.add(await uploadImageToCloudinary(file));
      }

      final batch = FirebaseFirestore.instance.batch();
      final chatRef = FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId);
      for (final url in urls) {
        batch.set(_messagesRef.doc(), {
          'senderUid': user.uid,
          'type': 'image',
          'imageUrl': url,
          'createdAt': FieldValue.serverTimestamp(),
        });
      }
      batch.update(chatRef, {
        'lastMessage': urls.length > 1
            ? '사진 ${urls.length}장을 보냈습니다'
            : '사진을 보냈습니다',
        'lastMessageAt': FieldValue.serverTimestamp(),
        'lastReadAt.${user.uid}': FieldValue.serverTimestamp(),
        'unreadCount.${widget.otherUid}': FieldValue.increment(urls.length),
      });
      await batch.commit();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('사진 전송에 실패했습니다: ${friendlyErrorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isSendingImage = false);
    }
  }

  /// 내가 보낸 메시지 버블 왼쪽에 카카오톡 스타일의 안읽음 표시('1')를 붙인다.
  /// 말풍선 옆에 (내 메시지면) 안읽음 '1'과 전송 시각을 함께 붙인다.
  Widget _withMeta({
    required bool isMine,
    required bool showUnread,
    required DateTime? createdAt,
    required Widget bubble,
  }) {
    final meta = Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (showUnread)
            const Padding(
              padding: EdgeInsets.only(bottom: 2),
              child: Text(
                '1',
                style: TextStyle(
                  fontSize: 11,
                  color: AppColors.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          if (createdAt != null)
            Text(
              _formatMessageTime(createdAt),
              style: const TextStyle(fontSize: 10, color: AppColors.inkMuted),
            ),
        ],
      ),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: isMine
          ? [meta, const SizedBox(width: 4), bubble]
          : [bubble, const SizedBox(width: 4), meta],
    );
  }

  void _openImageViewer(String url) {
    showDialog<void>(
      context: context,
      barrierColor: Colors.black,
      builder: (dialogContext) => Scaffold(
        backgroundColor: Colors.black,
        body: Stack(
          children: [
            GestureDetector(
              onTap: () => Navigator.pop(dialogContext),
              child: Center(
                child: InteractiveViewer(
                  child: CachedNetworkImage(imageUrl: url),
                ),
              ),
            ),
            SafeArea(
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(Icons.close, color: Colors.white),
                    tooltip: '닫기',
                    onPressed: () => Navigator.pop(dialogContext),
                  ),
                  IconButton(
                    icon: const Icon(
                      Icons.download_outlined,
                      color: Colors.white,
                    ),
                    tooltip: '사진 저장',
                    onPressed: () => saveImageToDevice(dialogContext, url),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _copyMessageText(String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('메시지를 복사했어요.')));
  }

  Future<void> _leaveChat() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '채팅방 나가기',
      content: '채팅방을 나가시겠습니까?\n나가면 이 채팅방은 목록에서 사라지고, 이전 메시지 기록도 더 이상 볼 수 없습니다.',
      confirmLabel: '나가기',
      danger: true,
    );
    if (!confirmed) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || !mounted) return;

    final navigator = Navigator.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({
            'clearedAt.$myUid': FieldValue.serverTimestamp(),
            'unreadCount.$myUid': 0,
          });
      navigator.pop();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('나가기에 실패했습니다: ${friendlyErrorMessage(e)}')),
        );
      }
    }
  }

  // 거래완료 요청/확인/완료 처리 버튼의 연속 탭으로 같은 작업이 중복
  // 실행되는 것을 막는다. 특히 완료 처리(_finalizeResolution)는 배너가
  // 서버 스냅샷으로 사라지기 전까지 계속 눌릴 수 있다.
  bool _isResolutionBusy = false;

  Future<void> _requestResolution() async {
    if (_isResolutionBusy) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    setState(() => _isResolutionBusy = true);
    try {
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
      // 게시글이 이미 삭제된 채팅방은 완료 처리 시 itemsCollection 업데이트가
      // 실패하는 막다른 흐름이 되므로, 애초에 요청 자체를 막는다.
      if (chatDoc.data()?['itemDeleted'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('삭제된 게시글은 거래완료 처리를 할 수 없어요.')),
          );
        }
        return;
      }

      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .set({'resolutionStatus': 'pending'}, SetOptions(merge: true));

      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('상대방에게 거래완료 확인을 요청했어요.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('요청에 실패했습니다: ${friendlyErrorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isResolutionBusy = false);
    }
  }

  Future<void> _confirmResolution() async {
    if (_isResolutionBusy) return;
    setState(() => _isResolutionBusy = true);
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .set({'resolutionStatus': 'confirmed'}, SetOptions(merge: true));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('확인에 실패했습니다: ${friendlyErrorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isResolutionBusy = false);
    }
  }

  Future<void> _finalizeResolution(String itemId) async {
    if (_isResolutionBusy) return;
    setState(() => _isResolutionBusy = true);
    try {
      try {
        await itemsCollection.doc(itemId).update({'resolved': true});
      } on FirebaseException catch (e) {
        // 배너를 띄운 뒤 게시글이 삭제되는 등, itemDeleted 플래그가 아직
        // 반영되기 전의 경합으로 이미 지워진 문서를 건드리게 될 수 있다.
        // 이 경우 게시글 쪽 업데이트만 건너뛰고 채팅 쪽 정리는 계속 진행한다.
        if (e.code != 'not-found') rethrow;
      }

      // 같은 글로 진행 중이던 다른 채팅이 있다면 그 쪽의 배너도 함께 정리한다
      // (현재 채팅방도 itemId가 같으므로 이 목록에 포함된다).
      // 채팅 목록(list) 규칙은 "결과가 전부 본인이 참여한 채팅"임을 쿼리
      // 조건만으로 증명해야 하므로 participants 필터가 반드시 필요하다.
      // 이 함수는 게시글 작성자만 실행하고, 작성자는 이 글의 모든 채팅방
      // 참여자라 결과는 동일하다.
      final myUid = FirebaseAuth.instance.currentUser?.uid;
      if (myUid == null) return;
      final relatedChats = await FirebaseFirestore.instance
          .collection('chats')
          .where('participants', arrayContains: myUid)
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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('처리에 실패했습니다: ${friendlyErrorMessage(e)}')),
        );
      }
    } finally {
      if (mounted) setState(() => _isResolutionBusy = false);
    }
  }

  Future<void> _revealRealName() async {
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null) return;

    final confirmed = await showConfirmDialog(
      context,
      title: '실명 공개',
      content:
          '상대방에게 가입 시 등록한 실명을 공개합니다.\n'
          '물품 인수·인계 등 신원 확인이 필요할 때만 사용해주세요.\n'
          '공개한 실명은 취소할 수 없습니다.',
      confirmLabel: '공개하기',
    );
    if (!confirmed) return;

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
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('실명 공개에 실패했습니다: ${friendlyErrorMessage(e)}')),
        );
      }
    }
  }

  Future<void> _blockUser() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '사용자 차단',
      content:
          '${widget.otherNickname}님을 차단하시겠습니까?\n차단하면 이 사용자는 더 이상 채팅을 걸거나 메시지를 보낼 수 없습니다.',
      confirmLabel: '차단',
      danger: true,
    );
    if (!confirmed) return;
    final myUid = FirebaseAuth.instance.currentUser?.uid;
    if (myUid == null || !mounted) return;

    final messenger = ScaffoldMessenger.of(context);
    try {
      // 차단은 이 채팅방을 목록에서 제외하는 것으로 충분하므로(차단한
      // 상대와의 채팅은 상대가 이후에 메시지를 보내도 항상 목록에서
      // 걸러진다), 나가기는 아래에서 별도로 물어본 뒤에만 처리한다.
      await FirebaseFirestore.instance.collection('blocks').doc(myUid).set({
        'blockedUsers': {widget.otherUid: widget.otherNickname},
      }, SetOptions(merge: true));
      messenger.showSnackBar(
        SnackBar(content: Text('${widget.otherNickname}님을 차단했습니다.')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('차단에 실패했습니다: ${friendlyErrorMessage(e)}')),
      );
      return;
    }

    if (!mounted) return;
    final shouldLeave = await showConfirmDialog(
      context,
      title: '채팅방 나가기',
      content:
          '이 채팅창을 나가시겠습니까?\n'
          '나가지 않아도 차단한 상대와의 대화는 채팅 목록에 다시 나타나지 않습니다.',
      cancelLabel: '아니요',
      confirmLabel: '나가기',
    );
    if (!shouldLeave || !mounted) return;

    final navigator = Navigator.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'clearedAt.$myUid': FieldValue.serverTimestamp()});
      navigator.pop();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(
          SnackBar(content: Text('나가기에 실패했습니다: ${friendlyErrorMessage(e)}')),
        );
      }
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
            StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('userPublicProfiles')
                  .doc(widget.otherUid)
                  .snapshots(),
              builder: (context, profileSnapshot) {
                return UserAvatar(
                  nickname: widget.otherNickname,
                  photoUrl:
                      profileSnapshot.data?.data()?['photoUrl'] as String?,
                  size: 34,
                );
              },
            ),
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
                  StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                    stream: FirebaseFirestore.instance
                        .collection('chats')
                        .doc(widget.chatId)
                        .snapshots(),
                    builder: (context, chatSnapshot) {
                      final typing = Map<String, dynamic>.from(
                        chatSnapshot.data?.data()?['typing'] as Map? ?? {},
                      );
                      final isOtherTyping =
                          typing[widget.otherUid] as bool? ?? false;
                      if (isOtherTyping) {
                        return const Text(
                          '입력 중...',
                          style: TextStyle(
                            fontSize: 12,
                            color: AppColors.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        );
                      }
                      return Text(
                        widget.itemTitle,
                        style: const TextStyle(
                          fontSize: 12,
                          color: AppColors.inkMuted,
                        ),
                        overflow: TextOverflow.ellipsis,
                      );
                    },
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
            stream: FirebaseFirestore.instance
                .collection('chats')
                .doc(widget.chatId)
                .snapshots(),
            builder: (context, snapshot) {
              final myUid = FirebaseAuth.instance.currentUser?.uid;
              final chatData = snapshot.data?.data();
              final itemAuthorUid = chatData?['itemAuthorUid'] as String?;
              final isOwner = myUid != null && myUid == itemAuthorUid;
              final itemDeleted = chatData?['itemDeleted'] == true;

              return PopupMenuButton<String>(
                icon: const Icon(Icons.more_vert),
                onSelected: (value) {
                  if (value == 'resolve') _requestResolution();
                  if (value == 'reveal') _revealRealName();
                  if (value == 'leave') _leaveChat();
                  if (value == 'block') _blockUser();
                },
                itemBuilder: (context) => [
                  // 거래완료 확인 요청은 게시글 작성자만, 그리고 게시글이
                  // 아직 남아있을 때만 할 수 있는 동작이다.
                  if (isOwner && !itemDeleted)
                    const PopupMenuItem(
                      value: 'resolve',
                      child: Text('거래완료 확인 요청하기'),
                    ),
                  const PopupMenuItem(value: 'reveal', child: Text('실명 공개하기')),
                  const PopupMenuItem(value: 'leave', child: Text('채팅방 나가기')),
                  const PopupMenuItem(
                    value: 'block',
                    child: Text(
                      '사용자 차단',
                      style: TextStyle(color: AppColors.danger),
                    ),
                  ),
                ],
              );
            },
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
              final itemDeleted = data['itemDeleted'] == true;
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

              if (itemDeleted) {
                banners.add(
                  const _ChatBanner(
                    icon: Icons.info_outline_rounded,
                    text: '이 채팅의 게시글은 삭제되었어요. 거래완료 처리는 더 이상 할 수 없어요.',
                  ),
                );
              } else if (resolutionStatus == 'pending') {
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
                          onAction: _isResolutionBusy
                              ? null
                              : _confirmResolution,
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
                    onAction: _isResolutionBusy
                        ? null
                        : () => _finalizeResolution(itemId),
                  ),
                );
              }

              if (banners.isEmpty) return const SizedBox.shrink();
              return Column(children: banners);
            },
          ),
          Expanded(
            // 내가 차단한 사용자 목록(내 소유 문서라 항상 읽을 수 있다).
            // 상대방이 나를 차단했는지는 알 수 없고 알 필요도 없다 —
            // 대신 각자 자신의 차단 목록을 기준으로 상대의 메시지를
            // 걸러내면, 차단당한 쪽은 평소처럼 메시지가 보내지고
            // 차단한 쪽에는 그 메시지가 전혀 보이지 않게 된다.
            child: Builder(
              builder: (context) {
                final myBlockedUids = AppUserData.of(context).blockedUids;

                return StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
                  stream: FirebaseFirestore.instance
                      .collection('chats')
                      .doc(widget.chatId)
                      .snapshots(),
                  builder: (context, chatSnapshot) {
                    final lastReadAt = Map<String, dynamic>.from(
                      chatSnapshot.data?.data()?['lastReadAt'] as Map? ?? {},
                    );
                    final otherLastReadAt =
                        lastReadAt[widget.otherUid] as Timestamp?;

                    return FutureBuilder<Timestamp?>(
                      future: _myClearedAtFuture,
                      builder: (context, clearedSnapshot) {
                        if (clearedSnapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                              color: AppColors.primary,
                            ),
                          );
                        }

                        final myClearedAt = clearedSnapshot.data;
                        Query<Map<String, dynamic>> query = _messagesRef
                            .orderBy('createdAt');
                        if (myClearedAt != null) {
                          query = query.where(
                            'createdAt',
                            isGreaterThan: myClearedAt,
                          );
                        }

                        return StreamBuilder<
                          QuerySnapshot<Map<String, dynamic>>
                        >(
                          stream: query.snapshots(),
                          builder: (context, snapshot) {
                            if (snapshot.hasError) {
                              return const FeedMessage(
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

                            // 내가 차단한 사용자가 보낸 메시지는 완전히
                            // 걸러내 마치 메시지가 오지 않은 것처럼 보이게 한다.
                            final docs = snapshot.data!.docs.where((doc) {
                              final senderUid = doc.data()['senderUid'];
                              return !myBlockedUids.contains(senderUid);
                            }).toList();
                            if (docs.isEmpty) {
                              return const FeedMessage(
                                icon: Icons.chat_bubble_outline_rounded,
                                title: '대화를 시작해보세요',
                                text: '물건의 상태나 전달 방법을\n첫 메시지로 보내보세요.',
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
                                final createdAt =
                                    data['createdAt'] as Timestamp?;
                                // 카카오톡처럼 내가 보낸 메시지를 상대방이
                                // 아직 읽지 않았으면 '1'을 표시한다.
                                final showUnread =
                                    isMine &&
                                    !(otherLastReadAt != null &&
                                        createdAt != null &&
                                        otherLastReadAt.compareTo(createdAt) >=
                                            0);

                                if (isImage) {
                                  final imageUrl =
                                      data['imageUrl'] as String? ?? '';
                                  return Align(
                                    alignment: isMine
                                        ? Alignment.centerRight
                                        : Alignment.centerLeft,
                                    child: _withMeta(
                                      isMine: isMine,
                                      showUnread: showUnread,
                                      createdAt: createdAt?.toDate(),
                                      bubble: GestureDetector(
                                        onTap: () => _openImageViewer(imageUrl),
                                        child: Container(
                                          margin: const EdgeInsets.only(
                                            bottom: 8,
                                          ),
                                          constraints: BoxConstraints(
                                            maxWidth:
                                                MediaQuery.of(
                                                  context,
                                                ).size.width *
                                                0.55,
                                          ),
                                          child: ClipRRect(
                                            borderRadius: BorderRadius.circular(
                                              kRadiusLg,
                                            ),
                                            child: CachedNetworkImage(
                                              imageUrl: imageUrl,
                                              fit: BoxFit.cover,
                                              errorWidget:
                                                  (
                                                    context,
                                                    url,
                                                    error,
                                                  ) => Container(
                                                    width: 160,
                                                    height: 160,
                                                    color: AppColors.surfaceAlt,
                                                    child: const Icon(
                                                      Icons
                                                          .broken_image_outlined,
                                                      color: AppColors.inkFaint,
                                                    ),
                                                  ),
                                            ),
                                          ),
                                        ),
                                      ),
                                    ),
                                  );
                                }

                                final messageText =
                                    data['text'] as String? ?? '';
                                return Align(
                                  alignment: isMine
                                      ? Alignment.centerRight
                                      : Alignment.centerLeft,
                                  child: _withMeta(
                                    isMine: isMine,
                                    showUnread: showUnread,
                                    createdAt: createdAt?.toDate(),
                                    bubble: GestureDetector(
                                      onLongPress: () =>
                                          _copyMessageText(messageText),
                                      child: Container(
                                        margin: const EdgeInsets.only(
                                          bottom: 8,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 10,
                                        ),
                                        constraints: BoxConstraints(
                                          maxWidth:
                                              MediaQuery.of(
                                                context,
                                              ).size.width *
                                              0.7,
                                        ),
                                        decoration: BoxDecoration(
                                          color: isMine
                                              ? AppColors.primary
                                              : AppColors.surfaceAlt,
                                          borderRadius: BorderRadius.only(
                                            topLeft: const Radius.circular(
                                              kRadiusLg,
                                            ),
                                            topRight: const Radius.circular(
                                              kRadiusLg,
                                            ),
                                            bottomLeft: Radius.circular(
                                              isMine ? kRadiusLg : 4,
                                            ),
                                            bottomRight: Radius.circular(
                                              isMine ? 4 : kRadiusLg,
                                            ),
                                          ),
                                        ),
                                        child: Text(
                                          messageText,
                                          style: TextStyle(
                                            color: isMine
                                                ? Colors.white
                                                : AppColors.ink,
                                          ),
                                        ),
                                      ),
                                    ),
                                  ),
                                );
                              },
                            );
                          },
                        );
                      },
                    );
                  },
                );
              },
            ),
          ),
          // 입력 바 — 상단 헤어라인으로 대화 영역과 구분하고, 알약 입력창 +
          // 채워진 원형 전송 버튼으로 구성한다.
          Container(
            decoration: const BoxDecoration(
              color: AppColors.surface,
              border: Border(top: BorderSide(color: AppColors.line)),
            ),
            child: SafeArea(
              top: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 12, 8),
                child: Row(
                  children: [
                    IconButton(
                      onPressed: _isSendingImage ? null : _sendImage,
                      tooltip: '사진 보내기',
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
                        onChanged: _onMessageChanged,
                        decoration: InputDecoration(
                          hintText: '메시지 입력',
                          hintStyle: const TextStyle(color: AppColors.inkFaint),
                          filled: true,
                          fillColor: AppColors.surfaceAlt,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 16,
                            vertical: 11,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(kRadiusPill),
                            borderSide: BorderSide.none,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(kRadiusPill),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(kRadiusPill),
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 1.6,
                            ),
                          ),
                        ),
                        onSubmitted: (_) => _send(),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Material(
                      color: AppColors.primary,
                      shape: const CircleBorder(),
                      child: InkWell(
                        customBorder: const CircleBorder(),
                        onTap: _send,
                        child: const Padding(
                          padding: EdgeInsets.all(10),
                          child: Icon(
                            Icons.arrow_upward_rounded,
                            size: 20,
                            color: Colors.white,
                            semanticLabel: '전송',
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// 메시지 전송 시각을 "오전/오후 h:mm" 형태로 표시한다.
String _formatMessageTime(DateTime time) {
  final isAm = time.hour < 12;
  final hour12 = time.hour % 12 == 0 ? 12 : time.hour % 12;
  final minute = time.minute.toString().padLeft(2, '0');
  return '${isAm ? '오전' : '오후'} $hour12:$minute';
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
      color: AppColors.primaryMuted,
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
