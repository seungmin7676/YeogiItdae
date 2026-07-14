import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

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
