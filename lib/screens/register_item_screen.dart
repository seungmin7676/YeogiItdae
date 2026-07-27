import 'dart:typed_data';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/lost_found_item.dart';
import '../services/analytics_service.dart';
import '../services/cloudinary_service.dart';
import '../services/error_messages.dart';
import '../services/push_sender.dart';
import '../theme/app_theme.dart';
import '../widgets/app_ui.dart';
import '../widgets/confirm_dialog.dart';
import '../widgets/image_source_sheet.dart';
import '../widgets/searchable_picker_sheet.dart';

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

  late String _selectedLocation;

  late final String _initialTitle;
  late final String _initialDescription;
  late final String _initialLocationDetail;
  late final ItemType _initialType;
  late final String _initialCategory;
  late final String _initialLocation;
  late final List<String> _initialImageUrls;

  bool get _isEditing => widget.editingItem != null;

  /// 뒤로가기 시 저장되지 않은 변경사항이 있는지 확인한다.
  bool get _hasUnsavedChanges =>
      _titleController.text.trim() != _initialTitle ||
      _descriptionController.text.trim() != _initialDescription ||
      _locationDetailController.text.trim() != _initialLocationDetail ||
      _selectedType != _initialType ||
      _selectedCategory != _initialCategory ||
      _selectedLocation != _initialLocation ||
      _newImages.isNotEmpty ||
      _existingImageUrls.length != _initialImageUrls.length;

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
      _selectedLocation = kLocations.contains(editing.location)
          ? editing.location
          : kLocations.first;
      _existingImageUrls = List.of(editing.imageUrls);
    } else {
      _selectedLocation = kLocations.first;
    }

    _initialTitle = _titleController.text;
    _initialDescription = _descriptionController.text;
    _initialLocationDetail = _locationDetailController.text;
    _initialType = _selectedType;
    _initialCategory = _selectedCategory;
    _initialLocation = _selectedLocation;
    _initialImageUrls = List.of(_existingImageUrls);

    _titleController.addListener(_onFieldChanged);
    _descriptionController.addListener(_onFieldChanged);
    _locationDetailController.addListener(_onFieldChanged);
  }

  void _onFieldChanged() {
    if (mounted) setState(() {});
  }

  Future<void> _pickImages() async {
    final remaining = _maxImages - _totalImageCount;
    if (remaining <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('사진은 최대 $_maxImages장까지 첨부할 수 있어요.')),
      );
      return;
    }
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
    final selected = picked.take(remaining).toList();
    final bytesList = await Future.wait(selected.map((f) => f.readAsBytes()));
    if (!mounted) return;
    setState(() {
      _newImages.addAll(selected);
      _newImageBytes.addAll(bytesList);
    });

    if (picked.length > remaining && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            '사진은 최대 $_maxImages장까지 첨부할 수 있어 ${picked.length - remaining}장은 제외됐어요.',
          ),
        ),
      );
    }
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

  Future<void> _pickLocation() async {
    final result = await showSearchablePickerSheet(
      context: context,
      title: '장소 선택',
      options: kLocations,
    );
    if (result != null) {
      setState(() => _selectedLocation = result);
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _locationDetailController.dispose();
    super.dispose();
  }

  /// 등록된 모든 사용자의 저장 키워드/구독 카테고리와 새 글을 비교해, 일치하는
  /// 사용자(본인 제외)에게 알림을 보낸다. 서버 함수 없이 클라이언트에서 직접
  /// 매칭하는 방식이라 사용자 수가 많아지면 이 한 번의 등록 작업이 읽는 문서
  /// 수도 함께 늘어난다는 한계가 있다. 키워드는 "부분 포함"까지 잡아내야
  /// 해서(예: 저장 키워드 "가방"이 글 제목 "책가방"에도 일치) Firestore
  /// 쿼리로 필터링할 수 없고, 결국 전체 savedSearches를 읽어 클라이언트에서
  /// 대조하는 방법뿐이다. 사용자 수가 아주 많아지면 이 한계를 넘기 위해
  /// (부분 포함 대신) 키워드를 토큰 단위로 정확히 매칭하는 방식으로 데이터
  /// 구조를 바꿔 arrayContainsAny 쿼리로 대상만 골라 읽는 재설계가 필요하다
  /// (매칭 정확도가 달라지는 변경이라 지금은 적용하지 않았다).
  ///
  /// 키워드와 카테고리가 둘 다 일치해도 한 사람에게는 알림을 한 번만
  /// 보낸다(키워드를 우선한다).
  Future<void> _notifyKeywordMatches({
    required String itemId,
    required String title,
    required String description,
    required String category,
    required String posterUid,
  }) async {
    final haystack = '$title $description'.toLowerCase();
    final snap = await FirebaseFirestore.instance
        .collection('savedSearches')
        .get();

    final matches = <(String recipientUid, String matchType, String keyword)>[];
    for (final doc in snap.docs) {
      if (doc.id == posterUid) continue;
      final data = doc.data();
      final keywords = List<String>.from(data['keywords'] as List? ?? const []);
      final matchedKeyword = keywords.firstWhere(
        (k) => k.trim().isNotEmpty && haystack.contains(k.trim().toLowerCase()),
        orElse: () => '',
      );
      final categories = List<String>.from(
        data['categories'] as List? ?? const [],
      );
      final matchedCategory = categories.contains(category) ? category : '';

      if (matchedKeyword.isEmpty && matchedCategory.isEmpty) continue;

      matches.add((
        doc.id,
        matchedKeyword.isNotEmpty ? 'keyword' : 'category',
        matchedKeyword.isNotEmpty ? matchedKeyword : matchedCategory,
      ));
    }
    if (matches.isEmpty) return;

    // Firestore 배치는 최대 500개 작업까지만 허용하므로, 일치한 사용자가
    // 많으면(예: 인기 카테고리를 수백 명이 구독) 청크로 나눠 커밋한다.
    // 그렇지 않으면 배치 전체가 실패해 매칭된 알림이 하나도 안 보내진다.
    const chunkSize = 450;
    for (var i = 0; i < matches.length; i += chunkSize) {
      final chunk = matches.sublist(
        i,
        (i + chunkSize) > matches.length ? matches.length : i + chunkSize,
      );
      final batch = FirebaseFirestore.instance.batch();
      for (final (recipientUid, matchType, keyword) in chunk) {
        batch
            .set(FirebaseFirestore.instance.collection('notifications').doc(), {
              'recipientUid': recipientUid,
              'senderUid': posterUid,
              'type': 'keyword_match',
              'matchType': matchType,
              'keyword': keyword,
              'itemId': itemId,
              'itemTitle': title,
              'read': false,
              'createdAt': FieldValue.serverTimestamp(),
            });
      }
      await batch.commit();
    }

    // 인앱 알림과 별개로, 각 구독자에게 백그라운드 푸시도 보낸다.
    for (final (recipientUid, matchType, keyword) in matches) {
      sendPush(
        recipientUid: recipientUid,
        type: 'keyword_match',
        title: title,
        body: matchType == 'category'
            ? "구독한 카테고리 '$keyword'에 새 글이 등록됐어요"
            : "저장한 키워드 '$keyword'와 일치하는 글이 등록됐어요",
        data: {'itemId': itemId, 'matchType': matchType, 'keyword': keyword},
      );
    }
  }

  Future<void> _submit() async {
    // 버튼 비활성화(UI)와 별개로, 리빌드 전에 연속 탭이 두 번 들어와도
    // 같은 글이 두 번 등록되지 않도록 메서드 진입 자체를 막는다.
    if (_isSubmitting) return;
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
        final ref = await itemsCollection.add(newItem.toMap());
        logItemRegistered(
          category: _selectedCategory,
          type: _selectedType.name,
        );
        // 키워드 알림 매칭 실패는 게시글 등록 자체를 막을 정도로 치명적이지
        // 않으므로 조용히 무시한다.
        try {
          await _notifyKeywordMatches(
            itemId: ref.id,
            title: title,
            description: description,
            category: _selectedCategory,
            posterUid: user.uid,
          );
        } catch (_) {}
      }
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() => _isSubmitting = false);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              '${_isEditing ? '수정' : '등록'}에 실패했습니다: ${friendlyErrorMessage(e)}',
            ),
          ),
        );
      }
    }
  }

  Future<void> _confirmDiscard() async {
    final confirmed = await showConfirmDialog(
      context,
      title: '나가시겠습니까?',
      content: '작성 중인 내용이 저장되지 않습니다.',
      cancelLabel: '계속 작성',
      confirmLabel: '나가기',
      danger: true,
    );
    if (confirmed && mounted) {
      Navigator.of(context).pop();
    }
  }

  /// 폼 공용 입력 데코레이션 — 섹션 라벨이 따로 있으므로 라벨 없이
  /// 채워진 필드만 쓴다.
  InputDecoration _fieldDecoration(String hint) {
    OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(kRadiusMd),
      borderSide: BorderSide(color: c, width: w),
    );
    return InputDecoration(
      hintText: hint,
      hintStyle: const TextStyle(color: AppColors.inkFaint, fontSize: 14),
      filled: true,
      fillColor: AppColors.surfaceAlt,
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      border: border(Colors.transparent),
      enabledBorder: border(Colors.transparent),
      focusedBorder: border(AppColors.primary, 1.6),
    );
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !_hasUnsavedChanges,
      onPopInvokedWithResult: (didPop, result) {
        if (didPop) return;
        _confirmDiscard();
      },
      child: Scaffold(
        backgroundColor: AppColors.bg,
        appBar: AppBar(title: Text(_isEditing ? '글 수정' : '글쓰기')),
        body: SingleChildScrollView(
          padding: const EdgeInsets.all(kPagePadding),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SectionLabel('사진 $_totalImageCount/$_maxImages'),
              const SizedBox(height: 10),
              SizedBox(
                height: 92,
                child: ListView(
                  scrollDirection: Axis.horizontal,
                  children: [
                    if (_totalImageCount < _maxImages)
                      GestureDetector(
                        onTap: _pickImages,
                        child: Semantics(
                          button: true,
                          label: '사진 추가',
                          child: Container(
                            width: 88,
                            height: 88,
                            margin: const EdgeInsets.only(right: 10),
                            decoration: BoxDecoration(
                              color: AppColors.surfaceAlt,
                              borderRadius: BorderRadius.circular(kRadiusMd),
                            ),
                            child: const Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(
                                  Icons.photo_camera_outlined,
                                  color: AppColors.inkMuted,
                                ),
                                SizedBox(height: 4),
                                Text(
                                  '사진 추가',
                                  style: TextStyle(
                                    color: AppColors.inkMuted,
                                    fontSize: 11,
                                    fontWeight: FontWeight.w600,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    for (var i = 0; i < _existingImageUrls.length; i++)
                      _ImagePickerTile(
                        key: ValueKey('existing_$i'),
                        onRemove: () => _removeExistingImage(i),
                        child: CachedNetworkImage(
                          imageUrl: _existingImageUrls[i],
                          width: 88,
                          height: 88,
                          fit: BoxFit.cover,
                          errorWidget: (context, url, error) => const Icon(
                            Icons.broken_image_outlined,
                            color: AppColors.inkFaint,
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
                  ],
                ),
              ),
              const SizedBox(height: 24),
              const SectionLabel('글 종류'),
              const SizedBox(height: 10),
              AppSegmented(
                labels: const ['습득 · 주웠어요', '분실 · 잃어버렸어요'],
                selectedIndex: _selectedType == ItemType.found ? 0 : 1,
                onChanged: (index) => setState(() {
                  _selectedType = index == 0 ? ItemType.found : ItemType.lost;
                }),
              ),
              const SizedBox(height: 24),
              const SectionLabel('물건 이름'),
              const SizedBox(height: 10),
              TextField(
                controller: _titleController,
                decoration: _fieldDecoration('예: 검은색 백팩, 아이폰 15'),
              ),
              const SizedBox(height: 24),
              const SectionLabel('카테고리'),
              const SizedBox(height: 10),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                decoration: BoxDecoration(
                  color: AppColors.surfaceAlt,
                  borderRadius: BorderRadius.circular(kRadiusMd),
                ),
                child: DropdownButtonHideUnderline(
                  child: DropdownButton<String>(
                    value: _selectedCategory,
                    isExpanded: true,
                    borderRadius: BorderRadius.circular(kRadiusMd),
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
              const SectionLabel('물건 세부 설명'),
              const SizedBox(height: 10),
              TextField(
                controller: _descriptionController,
                maxLines: 4,
                decoration: _fieldDecoration(
                  '색상, 브랜드, 특징 등 자세히 적어주시면 찾는 데 도움이 돼요.',
                ),
              ),
              const SizedBox(height: 24),
              SectionLabel(_selectedType == ItemType.found ? '발견 장소' : '분실 장소'),
              const SizedBox(height: 10),
              InkWell(
                borderRadius: BorderRadius.circular(kRadiusMd),
                onTap: _pickLocation,
                child: Container(
                  width: double.infinity,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 15,
                  ),
                  decoration: BoxDecoration(
                    color: AppColors.surfaceAlt,
                    borderRadius: BorderRadius.circular(kRadiusMd),
                  ),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _selectedLocation,
                          style: const TextStyle(
                            fontSize: 14,
                            color: AppColors.ink,
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      const Icon(
                        Icons.keyboard_arrow_down_rounded,
                        color: AppColors.inkMuted,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: _locationDetailController,
                decoration: _fieldDecoration('세부 위치 (예: 1층 북카페 창가 자리)'),
              ),
              const SizedBox(height: 24),
            ],
          ),
        ),
        // 저장 버튼은 하단에 고정 — 긴 폼을 끝까지 내리지 않아도 저장할 수
        // 있고, 키보드가 열리면 그 위로 따라 올라온다.
        bottomNavigationBar: Container(
          decoration: const BoxDecoration(
            color: AppColors.surface,
            border: Border(top: BorderSide(color: AppColors.line)),
          ),
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(
                kPagePadding,
                10,
                kPagePadding,
                12,
              ),
              child: ElevatedButton(
                onPressed: _isSubmitting || _titleController.text.trim().isEmpty
                    ? null
                    : _submit,
                child: _isSubmitting
                    ? const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          color: Colors.white,
                          strokeWidth: 2.5,
                        ),
                      )
                    : Text(
                        _titleController.text.trim().isEmpty
                            ? '물건 이름을 입력해주세요'
                            : (_isEditing ? '수정 완료' : '등록하기'),
                      ),
              ),
            ),
          ),
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
        borderRadius: BorderRadius.circular(kRadiusMd),
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
