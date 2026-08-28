import 'dart:async';

import 'package:firebase_analytics/firebase_analytics.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';

import 'firebase_options.dart';
import 'screens/auth_gate.dart';
import 'services/analytics_service.dart';
import 'services/backend_http.dart';
import 'services/push_notifications.dart';
import 'theme/app_theme.dart';
import 'widgets/app_user_data.dart';
import 'widgets/startup_failure_app.dart';

void main() {
  runZonedGuarded(() {
    WidgetsFlutterBinding.ensureInitialized();
    // Firebase 네이티브 초기화를 기다리기 전에 가벼운 첫 프레임을 먼저
    // 그린다. 초기화가 느린 기기에서도 검은 화면으로 멈춘 것처럼 보이지 않고,
    // Android가 시작 프레임 수백 개를 건너뛰는 현상도 줄어든다.
    runApp(const StartupLoadingApp());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_bootstrap());
    });
  }, (error, stack) => unawaited(_recordFatalError(error, stack)));
}

Future<void> _bootstrap() async {
  try {
    if (Firebase.apps.isEmpty) {
      await Firebase.initializeApp(
        options: DefaultFirebaseOptions.currentPlatform,
      );
    }

    // Crashlytics는 웹을 지원하지 않는다. Flutter 프레임워크가 잡아내는
    // 에러(위젯 build 중 예외 등)와, 프레임워크 밖(예: 마이크로태스크)에서
    // 나는 에러 둘 다 연결해야 실제로 발생하는 크래시를 놓치지 않는다.
    if (!kIsWeb) {
      FlutterError.onError =
          FirebaseCrashlytics.instance.recordFlutterFatalError;
      PlatformDispatcher.instance.onError = (error, stack) {
        unawaited(_recordFatalError(error, stack));
        return true;
      };
    }

    runApp(const MyApp());
    // App Check 토큰·FCM 토큰 네트워크 요청은 첫 프레임을 막지 않는다. 앱 UI를
    // 먼저 띄운 뒤 순서대로 준비해 콜드 스타트의 긴 정지와 skipped frames를 줄인다.
    unawaited(_initializeDeferredServices());
  } catch (error, stack) {
    await _recordFatalError(error, stack);
    runApp(StartupFailureApp(onRetry: _bootstrap));
  }
}

Future<void> _initializeDeferredServices() async {
  // 운영 백엔드는 App Check 실패를 기본 차단한다. Android Play Integrity와
  // iOS App Attest/DeviceCheck가 콘솔에 설정돼 있어야 인증·업로드 API가 동작한다.
  try {
    await ensureAppCheckActivated();
  } catch (error, stack) {
    await _recordFatalError(error, stack, fatal: false);
  }
  try {
    await PushNotifications.init();
  } catch (error, stack) {
    await _recordFatalError(error, stack, fatal: false);
  }
}

Future<void> _recordFatalError(
  Object error,
  StackTrace stack, {
  bool fatal = true,
}) async {
  if (kIsWeb || Firebase.apps.isEmpty) return;
  try {
    await FirebaseCrashlytics.instance.recordError(error, stack, fatal: fatal);
  } catch (_) {}
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
      // 앱 문구가 전부 한국어인데 Material 기본 문자열(텍스트 선택 메뉴의
      // Cut/Copy/Paste, 팝업 메뉴 툴팁 "Show menu" 등)만 영어로 나오던 것을
      // 맞춘다. 한국어 하나만 지원하므로 기기 언어와 무관하게 ko로 고정한다.
      locale: const Locale('ko'),
      supportedLocales: const [Locale('ko')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
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
      // 시스템 접근성 글자 크기를 앱 전역에서 제한하지 않는다. 고정 높이가
      // 필요한 공통 컨트롤은 scaledControlHeight로 배율에 맞춰 함께 커진다.
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
