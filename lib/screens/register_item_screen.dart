import 'dart:typed_data';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../models/lost_found_item.dart';
import '../services/cloudinary_service.dart';
import '../theme/app_theme.dart';

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
      _selectedLocation = _locations.contains(editing.location)
          ? editing.location
          : _locations.first;
      _existingImageUrls = List.of(editing.imageUrls);
    } else {
      _selectedLocation = _locations.first;
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

  Future<void> _confirmDiscard() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('나가시겠습니까?'),
        content: const Text('작성 중인 내용이 저장되지 않습니다.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('계속 작성'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('나가기', style: TextStyle(color: AppColors.danger)),
          ),
        ],
      ),
    );
    if (confirmed == true && mounted) {
      Navigator.of(context).pop();
    }
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
                    icon: Icon(Icons.inventory_2_outlined),
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
                  backgroundColor: AppColors.surface,
                  side: const BorderSide(color: AppColors.line),
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
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                ),
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
                          (loc) =>
                              DropdownMenuItem(value: loc, child: Text(loc)),
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
