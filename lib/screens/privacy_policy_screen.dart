import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

class PrivacyPolicyScreen extends StatelessWidget {
  const PrivacyPolicyScreen({super.key});

  static const _sections = <(String, String)>[
    (
      '1. 처리하는 개인정보',
      '필수: 한림대학교 이메일, 학번 또는 사번, 이름, 학과, Firebase 사용자 식별자\n'
          '선택·서비스 이용 중 생성: 닉네임, 프로필 사진, 게시글·채팅 내용과 첨부 이미지, 차단·찜·알림 설정, FCM 기기 토큰, 접속·오류·분석 로그',
    ),
    (
      '2. 이용 목적',
      '학교 구성원 인증, 계정·프로필 관리, 분실물 게시·검색·채팅·알림 제공, 신고·분쟁·도난 대응, 서비스 보안과 장애 분석을 위해 이용합니다. 실명·학과·학번은 일반 사용자에게 공개하지 않습니다.',
    ),
    (
      '3. 보유 및 파기',
      '계정과 이용 데이터는 회원 탈퇴 시 삭제합니다. 탈퇴자가 보낸 채팅 메시지와 이미지는 삭제하고 공유 채팅방에는 “탈퇴한 사용자”만 남깁니다. 재가입 제한을 위한 이메일의 SHA-256 해시와 제한 만료 시각은 탈퇴 후 30일간 보관한 뒤 삭제합니다. 법령상 별도 보존 의무가 있으면 해당 기간만 보관합니다.',
    ),
    (
      '4. 처리 위탁·국외 처리',
      '서비스 운영을 위해 Google Firebase(Auth, Firestore, Analytics, Crashlytics, Cloud Messaging, App Check), Cloudinary(이미지 저장·전송), Vercel(백엔드 호스팅), Google Gmail SMTP(인증 메일 발송)를 이용합니다. 해당 사업자의 해외 리전에 데이터가 저장·처리될 수 있으며, 전송 시 암호화된 연결을 사용합니다.',
    ),
    (
      '5. 이용자의 권리',
      '앱의 마이페이지 > 회원 탈퇴에서 계정과 개인정보 삭제를 직접 요청할 수 있습니다. 앱을 사용할 수 없는 경우 공개 웹사이트의 “계정 삭제 요청” 안내에 따라 가입한 학교 이메일로 요청할 수 있습니다. 개인정보 열람·정정·삭제·처리정지 또는 동의 철회가 필요하면 아래 연락처로 요청해 주세요. 필수 정보 수집에 동의하지 않을 수 있으나, 학교 구성원 전용 서비스 가입은 제한됩니다.',
    ),
    (
      '6. 보호 조치',
      '학교 이메일 인증, Firebase Security Rules, App Check, 요청 횟수 제한, 최소 권한 접근, 전송 구간 암호화, 관리자 전용 접근 통제를 적용합니다.',
    ),
    (
      '7. 개인정보 보호 문의',
      '처리자: 여기있대! 운영팀\n이메일: 20225216@hallym.ac.kr\n시행·최종 수정일: 2026년 8월 27일',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.bg,
      appBar: AppBar(title: const Text('개인정보 처리방침')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(kPagePadding, 24, kPagePadding, 40),
        children: [
          const Text(
            '여기있대! 개인정보 처리방침',
            style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
          ),
          const SizedBox(height: 10),
          const Text(
            '여기있대!는 한림대학교 구성원이 안심하고 분실물을 찾을 수 있도록 필요한 정보만 처리합니다.',
            style: TextStyle(color: AppColors.inkMuted, height: 1.6),
          ),
          const SizedBox(height: 28),
          for (final (title, body) in _sections) ...[
            Text(
              title,
              style: const TextStyle(fontSize: 16, fontWeight: FontWeight.w800),
            ),
            const SizedBox(height: 8),
            Text(
              body,
              style: const TextStyle(
                fontSize: 14,
                height: 1.65,
                color: AppColors.inkMuted,
              ),
            ),
            const SizedBox(height: 24),
          ],
        ],
      ),
    );
  }
}
