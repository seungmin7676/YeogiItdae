import 'dart:async';

import 'package:cached_network_image/cached_network_image.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

import '../models/lost_found_item.dart';
import '../services/analytics_service.dart';
import '../services/cloudinary_service.dart';
import '../services/error_messages.dart';
import '../services/keyword_notifier.dart';
import '../services/media_deletion.dart';
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

  // 입력 길이 상한. 제목이 지나치게 길면 목록·상세·알림·공유 문구가 모두
  // 무너지고, 본문은 Firestore 문서 크기(1MB)까지 붙여 넣을 수 있어 비용과
  // 남용 위험이 있다. 화면에서 자연스럽게 읽히는 선에서 잘라둔다.
  static const int _maxTitleLength = 40;
  static const int _maxDescriptionLength = 1000;
  static const int _maxLocationDetailLength = 50;
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

    final uploadedUrls = <String>[];
    var itemPersisted = false;
    String? cleanupWarning;
    try {
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
        itemPersisted = true;
        final removedUrls = editing.imageUrls.where(
          (url) => !imageUrls.contains(url),
        );
        try {
          await deleteUploadedMedia(removedUrls);
        } catch (e) {
          cleanupWarning =
              '수정은 완료됐지만 제거한 이미지 정리를 마치지 못했습니다: '
              '${friendlyErrorMessage(e)}';
        }
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
        itemPersisted = true;
        logItemRegistered(
          category: _selectedCategory,
          type: _selectedType.name,
        );
        // 키워드·카테고리 구독자 매칭과 알림 발송은 백엔드가 맡는다
        // (keyword_notifier.dart 참고 — 예전에는 클라이언트가 남의
        // savedSearches를 전부 읽어야 했다). 실패해도 글은 이미 등록됐으므로
        // 결과를 기다리지 않는다.
        unawaited(notifyKeywordMatches(itemId: ref.id));
      }
      if (mounted) {
        Navigator.pop(context);
        if (cleanupWarning != null) {
          ScaffoldMessenger.of(
            context,
          ).showSnackBar(SnackBar(content: Text(cleanupWarning)));
        }
      }
    } catch (e) {
      if (!itemPersisted) {
        try {
          await deleteUploadedMedia(uploadedUrls);
        } catch (_) {}
      }
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
    // 업로드·등록이 진행 중일 때는 "작성 중인 내용이 저장되지 않습니다"가
    // 사실과 다르다(이미 저장 중이다). 끝날 때까지 기다리게 안내한다.
    if (_isSubmitting) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('${_isEditing ? '수정' : '등록'}하는 중이에요. 잠시만 기다려주세요.'),
        ),
      );
      return;
    }
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
    final thumbDecodeSize = (88 * MediaQuery.devicePixelRatioOf(context))
        .round();
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
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: kFormMaxWidth),
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
                                  borderRadius: BorderRadius.circular(
                                    kRadiusMd,
                                  ),
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
                        // 88dp 썸네일 자리에 1600px 원본을 그대로 디코딩하지 않도록
                        // 표시 크기에 맞춰 디코딩 폭을 제한한다.
                        for (var i = 0; i < _existingImageUrls.length; i++)
                          _ImagePickerTile(
                            key: ValueKey('existing_$i'),
                            onRemove: () => _removeExistingImage(i),
                            child: CachedNetworkImage(
                              imageUrl: _existingImageUrls[i],
                              width: 88,
                              height: 88,
                              fit: BoxFit.cover,
                              memCacheWidth: thumbDecodeSize,
                              memCacheHeight: thumbDecodeSize,
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
                              cacheWidth: thumbDecodeSize,
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
                      _selectedType = index == 0
                          ? ItemType.found
                          : ItemType.lost;
                    }),
                  ),
                  const SizedBox(height: 24),
                  const SectionLabel('물건 이름'),
                  const SizedBox(height: 10),
                  TextField(
                    controller: _titleController,
                    maxLength: _maxTitleLength,
                    textInputAction: TextInputAction.next,
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
                            .map(
                              (c) => DropdownMenuItem(value: c, child: Text(c)),
                            )
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
                    maxLength: _maxDescriptionLength,
                    maxLengthEnforcement: MaxLengthEnforcement.enforced,
                    decoration: _fieldDecoration(
                      '색상, 브랜드, 특징 등 자세히 적어주시면 찾는 데 도움이 돼요.',
                    ),
                  ),
                  const SizedBox(height: 24),
                  SectionLabel(
                    _selectedType == ItemType.found ? '발견 장소' : '분실 장소',
                  ),
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
                    maxLength: _maxLocationDetailLength,
                    textInputAction: TextInputAction.done,
                    decoration: _fieldDecoration('세부 위치 (예: 1층 북카페 창가 자리)'),
                  ),
                  const SizedBox(height: 24),
                ],
              ),
            ),
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
            child: Align(
              heightFactor: 1,
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: kFormMaxWidth),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    kPagePadding,
                    10,
                    kPagePadding,
                    12,
                  ),
                  child: ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      minimumSize: Size.fromHeight(
                        scaledControlHeight(context, 52),
                      ),
                    ),
                    onPressed:
                        _isSubmitting || _titleController.text.trim().isEmpty
                        ? null
                        : _submit,
                    child: _isSubmitting
                        ? const SizedBox(
                            width: 22,
                            height: 22,
                            child: CircularProgressIndicator(
                              color: Colors.white,
                              strokeWidth: 2.5,
                              semanticsLabel: '게시글 저장 중',
                            ),
                          )
                        : Text(
                            _titleController.text.trim().isEmpty
                                ? '물건 이름을 입력해주세요'
                                : (_isEditing ? '수정 완료' : '등록하기'),
                            maxLines: 2,
                            textAlign: TextAlign.center,
                          ),
                  ),
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
          // 보이는 원은 작지만(20dp) 터치 영역은 투명 여백까지 포함해
          // 손가락으로 정확히 누를 수 있는 크기로 넓힌다.
          Positioned(
            top: 0,
            right: 0,
            child: Semantics(
              button: true,
              label: '사진 삭제',
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: onRemove,
                child: const Padding(
                  padding: EdgeInsets.all(8),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: Colors.black54,
                      shape: BoxShape.circle,
                    ),
                    child: Padding(
                      padding: EdgeInsets.all(3),
                      child: Icon(Icons.close, color: Colors.white, size: 14),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
