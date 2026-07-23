import 'dart:convert';

import 'package:firebase_auth/firebase_auth.dart';
import 'package:http/http.dart' as http;
import 'package:image_picker/image_picker.dart';

import 'backend_exception.dart';

/// 로그인한 사용자만 업로드할 수 있도록, cloud name/preset을 클라이언트에
/// 고정해두지 않고 매번 백엔드(verify_backend)에서 서명을 발급받아 함께
/// 보낸다. 이전에는 unsigned upload preset을 그대로 썼는데, cloud
/// name/preset 이름은 APK·웹 번들만 열어봐도 알 수 있어 앱을 거치지 않고도
/// 누구나 이 계정에 직접 업로드할 수 있는(무료 티어 용량/대역폭을 앱과
/// 무관한 제3자가 소진시킬 수 있는) 위험이 있었다.
///
/// 선택한 이미지를 Cloudinary에 업로드하고 접근 가능한 URL을 반환한다.
Future<String> uploadImageToCloudinary(XFile file) async {
  final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();
  if (idToken == null) {
    throw Exception('로그인이 필요합니다.');
  }

  final signResponse = await http.post(
    Uri.parse('$kVerifyBackendUrl/api/cloudinary-signature'),
    headers: {
      'Content-Type': 'application/json',
      'Authorization': 'Bearer $idToken',
    },
  );
  final signDecoded = signResponse.body.isEmpty
      ? <String, dynamic>{}
      : jsonDecode(signResponse.body) as Map<String, dynamic>;
  if (signResponse.statusCode >= 400) {
    throw BackendException(signDecoded['error'] as String? ?? 'unknown');
  }

  final cloudName = signDecoded['cloudName'] as String;
  final bytes = await file.readAsBytes();
  final uri = Uri.parse(
    'https://api.cloudinary.com/v1_1/$cloudName/image/upload',
  );

  final request = http.MultipartRequest('POST', uri)
    ..fields['api_key'] = signDecoded['apiKey'] as String
    ..fields['timestamp'] = signDecoded['timestamp'].toString()
    ..fields['signature'] = signDecoded['signature'] as String
    ..fields['upload_preset'] = signDecoded['uploadPreset'] as String
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
