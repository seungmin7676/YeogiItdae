import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/lost_found_item.dart';
import '../services/cloudinary_service.dart';
import '../theme/app_theme.dart';
import '../widgets/feed_message.dart';
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

  /// 내가 보낸 메시지 버블 왼쪽에 카카오톡 스타일의 안읽음 표시('1')를 붙인다.
  Widget _withUnreadMark({required bool show, required Widget bubble}) {
    if (!show) return bubble;
    return Row(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        const Padding(
          padding: EdgeInsets.only(right: 4, bottom: 8),
          child: Text(
            '1',
            style: TextStyle(
              fontSize: 11,
              color: AppColors.primary,
              fontWeight: FontWeight.w700,
            ),
          ),
        ),
        bubble,
      ],
    );
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
        title: const Text('채팅방 나가기'),
        content: const Text(
          '채팅방을 나가시겠습니까?\n나가면 이 채팅방은 목록에서 사라지고, 이전 메시지 기록도 더 이상 볼 수 없습니다.',
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
      messenger.showSnackBar(SnackBar(content: Text('차단에 실패했습니다: $e')));
      return;
    }

    if (!mounted) return;
    final shouldLeave = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('채팅방 나가기'),
        content: const Text(
          '이 채팅창을 나가시겠습니까?\n'
          '나가지 않아도 차단한 상대와의 대화는 채팅 목록에 다시 나타나지 않습니다.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('아니요'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('나가기'),
          ),
        ],
      ),
    );
    if (shouldLeave != true || !mounted) return;

    final navigator = Navigator.of(context);
    try {
      await FirebaseFirestore.instance
          .collection('chats')
          .doc(widget.chatId)
          .update({'clearedAt.$myUid': FieldValue.serverTimestamp()});
      navigator.pop();
    } catch (e) {
      if (mounted) {
        messenger.showSnackBar(SnackBar(content: Text('나가기에 실패했습니다: $e')));
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
            // 내가 차단한 사용자 목록(내 소유 문서라 항상 읽을 수 있다).
            // 상대방이 나를 차단했는지는 알 수 없고 알 필요도 없다 —
            // 대신 각자 자신의 차단 목록을 기준으로 상대의 메시지를
            // 걸러내면, 차단당한 쪽은 평소처럼 메시지가 보내지고
            // 차단한 쪽에는 그 메시지가 전혀 보이지 않게 된다.
            child: StreamBuilder<DocumentSnapshot<Map<String, dynamic>>>(
              stream: FirebaseFirestore.instance
                  .collection('blocks')
                  .doc(myUid ?? '_')
                  .snapshots(),
              builder: (context, myBlocksSnapshot) {
                final myBlockedUids = Set<String>.from(
                  (myBlocksSnapshot.data?.data()?['blockedUsers'] as Map?)
                          ?.keys ??
                      const [],
                );

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
                                    child: _withUnreadMark(
                                      show: showUnread,
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
                                              16,
                                            ),
                                            child: Image.network(
                                              imageUrl,
                                              fit: BoxFit.cover,
                                              errorBuilder:
                                                  (
                                                    context,
                                                    error,
                                                    stackTrace,
                                                  ) => Container(
                                                    width: 160,
                                                    height: 160,
                                                    color: AppColors.bg,
                                                    child: const Icon(
                                                      Icons
                                                          .broken_image_outlined,
                                                      color: Color(0xFFC7CAD6),
                                                    ),
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
                                  child: _withUnreadMark(
                                    show: showUnread,
                                    bubble: Container(
                                      margin: const EdgeInsets.only(bottom: 8),
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 10,
                                      ),
                                      constraints: BoxConstraints(
                                        maxWidth:
                                            MediaQuery.of(context).size.width *
                                            0.7,
                                      ),
                                      decoration: BoxDecoration(
                                        color: isMine
                                            ? AppColors.primary
                                            : Colors.white,
                                        borderRadius: BorderRadius.circular(16),
                                        border: isMine
                                            ? null
                                            : Border.all(color: AppColors.line),
                                      ),
                                      child: Text(
                                        data['text'] as String? ?? '',
                                        style: TextStyle(
                                          color: isMine
                                              ? Colors.white
                                              : AppColors.ink,
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
