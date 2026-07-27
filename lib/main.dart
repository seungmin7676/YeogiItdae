import 'dart:async';

import 'package:firebase_app_check/firebase_app_check.dart';
import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/analytics_service.dart';
import 'services/push_notifications.dart';
import 'theme/app_theme.dart';
import 'widgets/app_user_data.dart';

void main() {
  runZonedGuarded(
    () async {
      WidgetsFlutterBinding.ensureInitialized();
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );

      // 이 앱에서 온 요청인지 검증해, 학번 패턴을 순회하며 임의 주소로 인증/재설정
      // 메일을 대량 발송시키는 등의 남용을 막는다. Android는 Play Integrity,
      // iOS는 App Attest를 쓰고, 아직 콘솔에서 활성화하지 않았다면(Play
      // Integrity API 활성화, SHA-256 지문 등록 등 수동 설정이 필요하다) 토큰
      // 발급이 실패할 수 있는데, 그래도 앱 자체는 계속 정상 동작해야 하므로
      // 실패를 무시한다 — 서버 쪽도 검증 실패를 당장 차단하지 않고 로그만
      // 남기도록 되어 있다(APP_CHECK_ENFORCE 환경변수로 나중에 강제할 수 있다).
      try {
        await FirebaseAppCheck.instance.activate(
          providerAndroid: AndroidPlayIntegrityProvider(),
          providerApple: AppleAppAttestWithDeviceCheckFallbackProvider(),
        );
      } catch (_) {}

      // Crashlytics는 웹을 지원하지 않는다. Flutter 프레임워크가 잡아내는
      // 에러(위젯 build 중 예외 등)와, 프레임워크 밖(예: 마이크로태스크)에서
      // 나는 에러 둘 다 연결해야 실제로 발생하는 크래시를 놓치지 않는다.
      if (!kIsWeb) {
        FlutterError.onError =
            FirebaseCrashlytics.instance.recordFlutterFatalError;
        PlatformDispatcher.instance.onError = (error, stack) {
          FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
          return true;
        };
      }

      // 푸시 알림(권한·토큰·핸들러) 초기화. 실패해도 앱은 계속 떠야 하므로
      // 삼켜서 처리한다(예: 웹, 권한 거부, FCM 설정 미비).
      try {
        await PushNotifications.init();
      } catch (_) {}

      runApp(const MyApp());
    },
    (error, stack) {
      if (!kIsWeb) {
        FirebaseCrashlytics.instance.recordError(error, stack, fatal: true);
      }
    },
  );
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    final base = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      primary: AppColors.primary,
    );
    return MaterialApp(
      title: '여기있대!',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        fontFamily: 'Pretendard',
        colorScheme: base.copyWith(surface: AppColors.surface),
        scaffoldBackgroundColor: AppColors.bg,
        // 아이콘 굵기·크기를 20pt로 통일한다 — 화면마다 따로 size를 안 줘도
        // 미니멀한 라인 아이콘 톤이 자동으로 맞춰지도록.
        iconTheme: const IconThemeData(size: 20, color: AppColors.inkMuted),
        primaryIconTheme: const IconThemeData(
          size: 20,
          color: AppColors.inkMuted,
        ),
        // v3는 순백 캔버스라 색으로 위계를 만들 수 없다 — 크기·굵기·명도의
        // 대비를 v2보다 한 단계씩 키워 타이포그래피가 구조를 만들게 한다.
        textTheme: const TextTheme(
          titleLarge: TextStyle(
            color: AppColors.ink,
            fontSize: 26,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.7,
            height: 1.25,
          ),
          titleMedium: TextStyle(
            color: AppColors.ink,
            fontSize: 18,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
          titleSmall: TextStyle(
            color: AppColors.ink,
            fontSize: 15,
            fontWeight: FontWeight.w700,
            letterSpacing: -0.2,
          ),
          bodyLarge: TextStyle(
            color: AppColors.ink,
            fontSize: 15.5,
            height: 1.55,
          ),
          bodyMedium: TextStyle(
            color: AppColors.ink,
            fontSize: 14,
            height: 1.55,
          ),
          bodySmall: TextStyle(color: AppColors.inkMuted, fontSize: 12.5),
          labelLarge: TextStyle(
            color: AppColors.ink,
            fontSize: 14,
            fontWeight: FontWeight.w600,
          ),
        ).apply(bodyColor: AppColors.ink, displayColor: AppColors.ink),
        // 모든 앱바 아래에 헤어라인을 깔아 순백 배경에서도 고정 영역과
        // 스크롤 영역의 경계가 구조적으로 드러나게 한다.
        appBarTheme: const AppBarTheme(
          backgroundColor: AppColors.bg,
          foregroundColor: AppColors.ink,
          elevation: 0,
          scrolledUnderElevation: 0,
          centerTitle: false,
          shape: Border(bottom: BorderSide(color: AppColors.line)),
          titleTextStyle: TextStyle(
            color: AppColors.ink,
            fontSize: 19,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.4,
          ),
        ),
        // 버튼은 알약 — 각진 라운드의 콘텐츠(썸네일·시트)와 형태로 구분되는
        // "누르는 것"의 언어.
        elevatedButtonTheme: ElevatedButtonThemeData(
          style: ElevatedButton.styleFrom(
            backgroundColor: AppColors.primary,
            foregroundColor: Colors.white,
            disabledBackgroundColor: AppColors.surfaceAlt,
            disabledForegroundColor: AppColors.inkFaint,
            elevation: 0,
            minimumSize: const Size.fromHeight(52),
            textStyle: const TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.w700,
              letterSpacing: -0.2,
            ),
            shape: const StadiumBorder(),
          ),
        ),
        outlinedButtonTheme: OutlinedButtonThemeData(
          style: OutlinedButton.styleFrom(
            foregroundColor: AppColors.ink,
            side: const BorderSide(color: AppColors.lineStrong),
            minimumSize: const Size.fromHeight(48),
            textStyle: const TextStyle(
              fontSize: 14.5,
              fontWeight: FontWeight.w600,
            ),
            shape: const StadiumBorder(),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.primary,
            textStyle: const TextStyle(fontWeight: FontWeight.w600),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(kRadiusSm),
            ),
          ),
        ),
        floatingActionButtonTheme: const FloatingActionButtonThemeData(
          backgroundColor: AppColors.ink,
          foregroundColor: Colors.white,
          elevation: 0,
          highlightElevation: 0,
          shape: StadiumBorder(),
        ),
        dialogTheme: DialogThemeData(
          backgroundColor: AppColors.surface,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusLg),
          ),
          titleTextStyle: const TextStyle(
            color: AppColors.ink,
            fontSize: 17,
            fontWeight: FontWeight.w800,
            letterSpacing: -0.2,
          ),
          contentTextStyle: const TextStyle(
            color: AppColors.inkMuted,
            fontSize: 14,
            height: 1.5,
          ),
        ),
        snackBarTheme: SnackBarThemeData(
          behavior: SnackBarBehavior.floating,
          backgroundColor: AppColors.ink,
          contentTextStyle: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.w600,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(kRadiusMd),
          ),
        ),
        // 하단 내비게이션 — 인디케이터 pill 없이 아이콘·라벨 색만으로 선택
        // 상태를 표현하는 플랫 바.
        navigationBarTheme: NavigationBarThemeData(
          backgroundColor: AppColors.surface,
          elevation: 0,
          height: 64,
          indicatorColor: Colors.transparent,
          labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
          labelTextStyle: WidgetStateProperty.resolveWith(
            (states) => TextStyle(
              fontSize: 11,
              fontWeight: states.contains(WidgetState.selected)
                  ? FontWeight.w700
                  : FontWeight.w600,
              color: states.contains(WidgetState.selected)
                  ? AppColors.ink
                  : AppColors.inkFaint,
            ),
          ),
        ),
        dividerTheme: const DividerThemeData(
          color: AppColors.line,
          thickness: 1,
          space: 1,
        ),
      ),
      navigatorKey: rootNavigatorKey,
      builder: (context, child) =>
          AppUserDataProvider(child: child ?? const SizedBox.shrink()),
      // 대부분의 화면 전환이 이름 없는 라우트(Navigator.push +
      // MaterialPageRoute)라 화면 이름 자체는 잡히지 않지만, 그래도 화면
      // 전환 빈도·세션 길이 같은 기본 지표는 자동으로 남는다.
      navigatorObservers: [FirebaseAnalyticsObserver(analytics: analytics)],
      home: const AuthGate(),
    );
  }
}
