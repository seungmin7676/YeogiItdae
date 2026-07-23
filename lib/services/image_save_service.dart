import 'package:flutter/material.dart';
import 'package:gal/gal.dart';
import 'package:http/http.dart' as http;

import 'error_messages.dart';

/// 네트워크 이미지를 다운로드해 기기 갤러리(사진첩)에 저장한다.
/// 저장 성공/실패를 스낵바로 알려준다.
Future<void> saveImageToDevice(BuildContext context, String imageUrl) async {
  try {
    final response = await http.get(Uri.parse(imageUrl));
    if (response.statusCode >= 400) {
      throw Exception('이미지를 다운로드하지 못했습니다 (${response.statusCode})');
    }
    await Gal.putImageBytes(response.bodyBytes);
    if (!context.mounted) return;
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('사진을 저장했어요.')));
  } catch (e) {
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('사진 저장에 실패했습니다: ${friendlyErrorMessage(e)}')),
    );
  }
}
