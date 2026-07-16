import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../theme/app_theme.dart';

/// 사진 첨부 방식을 고르는 바텀시트. 카메라로 찍거나 갤러리에서 고를 수 있다.
/// null을 반환하면 아무것도 선택하지 않고 닫은 것이다.
Future<ImageSource?> showImageSourceSheet(BuildContext context) {
  return showModalBottomSheet<ImageSource>(
    context: context,
    backgroundColor: Colors.white,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
    ),
    builder: (context) => SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          ListTile(
            leading: const Icon(
              Icons.photo_camera_outlined,
              color: AppColors.primary,
            ),
            title: const Text('카메라로 촬영'),
            onTap: () => Navigator.pop(context, ImageSource.camera),
          ),
          ListTile(
            leading: const Icon(Icons.photo_outlined, color: AppColors.primary),
            title: const Text('갤러리에서 선택'),
            onTap: () => Navigator.pop(context, ImageSource.gallery),
          ),
        ],
      ),
    ),
  );
}
