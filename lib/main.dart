/// 搜谱 — 双平台(弹琴吧/虫虫钢琴)曲谱客户端。
/// 初始化按 PiliPlus 模式: MediaKit / edge-to-edge / DisplayMode /
/// Windows WebViewEnvironment / window_manager / SmartDialog / 动态取色。
library;

import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_smart_dialog/flutter_smart_dialog.dart';
import 'package:get/get.dart';
import 'package:media_kit/media_kit.dart';
import 'package:window_manager/window_manager.dart';

import 'common/constants.dart';
import 'http/http.dart';
import 'pages/home_page.dart';
import 'pages/mine_list_page.dart';
import 'pages/score_detail_page.dart';
import 'pages/sheet_web_page.dart' show initWebViewEnv;
import 'services/player_service.dart';
import 'services/sessions.dart';
import 'utils/globals.dart';
import 'utils/platform_utils.dart';
import 'widgets/player_bar.dart';

const _fallbackSeed = Color(0xFF5E4B8B);

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  MediaKit.ensureInitialized();

  await GPaths.init();
  Http.init(cookieDir: GPaths.cookiesTan8);
  await Sessions.init();
  final player = Get.put(PlayerService(), permanent: true);
  await player.initializeBackground();

  if (PlatformUtils.isWindows &&
      (await WebViewEnvironment.getAvailableVersion()) != null) {
    initWebViewEnv(
      await WebViewEnvironment.create(
        settings: WebViewEnvironmentSettings(
          userDataFolder: '${GPaths.appSupport}/flutter_inappwebview',
        ),
      ),
    );
  }

  if (PlatformUtils.isMobile) {
    // android edge-to-edge (照抄 PiliPlus 平台特调)
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);
    SystemChrome.setSystemUIOverlayStyle(
      const SystemUiOverlayStyle(
        systemNavigationBarColor: Colors.transparent,
        systemNavigationBarDividerColor: Colors.transparent,
        statusBarColor: Colors.transparent,
        systemNavigationBarContrastEnforced: false,
      ),
    );
    if (Platform.isAndroid) {
      try {
        final supported = await FlutterDisplayMode.supported;
        const auto = DisplayMode.auto;
        if (supported.contains(auto) || supported.isNotEmpty) {
          await FlutterDisplayMode.setPreferredMode(auto);
        }
      } catch (_) {}
    }
  }

  if (PlatformUtils.isDesktop) {
    await windowManager.ensureInitialized();
    final win = windowManager;
    await win.ensureInitialized();
    await win.setTitleBarStyle(
      TitleBarStyle.normal,
      windowButtonVisibility: true,
    );
    const minWidth = 520.0, minHeight = 500.0;
    await win.setMinimumSize(const Size(minWidth, minHeight));
    await win.setSize(const Size(640, 720));
    await win.center();
    await win.setTitle(AppMeta.appName);
    await win.show();
  }

  FocusManager.instance.addEarlyKeyEventHandler(_onKeyEvent);

  runApp(const MyApp());
}

KeyEventResult _onKeyEvent(KeyEvent event) {
  if (event is KeyDownEvent && event.logicalKey == LogicalKeyboardKey.escape) {
    if (SmartDialog.checkExist()) {
      SmartDialog.dismiss();
      return KeyEventResult.handled;
    }
    final navigator = Get.key.currentState;
    if (navigator != null && navigator.canPop()) {
      navigator.pop();
      return KeyEventResult.handled;
    }
  }
  return KeyEventResult.ignored;
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // material_ui 的 ColorScheme 与 flutter/material 的不互通(dynamic_color 2.1.0
    // 返回的是 material_ui 方案), 改为保证可用: 系统动态取色以 seed 兜底。
    final l = ColorScheme.fromSeed(seedColor: _fallbackSeed);
    final d = ColorScheme.fromSeed(
      seedColor: _fallbackSeed,
      brightness: Brightness.dark,
    );
    return GetMaterialApp(
      title: AppMeta.appName,
      theme: _theme(l),
      darkTheme: _theme(d),
      themeMode: ThemeMode.system,
      locale: const Locale('zh', 'CN'),
      fallbackLocale: const Locale('zh', 'CN'),
      supportedLocales: const [Locale('zh', 'CN'), Locale('en', 'US')],
      localizationsDelegates: const [
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      initialRoute: '/',
      routingCallback: (routing) {
        final onHome = (routing?.current ?? '/') == '/';
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (playerOnHome.value != onHome) playerOnHome.value = onHome;
        });
      },
      getPages: [
        GetPage(name: '/', page: () => const HomePage()),
        GetPage(
          name: '/score',
          page: () => ScoreDetailPage(
            platform: Get.parameters['platform'] ?? 'cc',
            id: Get.parameters['id'] ?? '',
          ),
        ),
        GetPage(
          name: '/mine_list',
          page: () =>
              MineListPage(kind: Get.parameters['kind'] ?? 'cc_collect'),
        ),
      ],
      builder: FlutterSmartDialog.init(
        builder: (context, child) => ValueListenableBuilder<bool>(
          valueListenable: playerOnHome,
          builder: (context, onHome, _) => Column(
            children: [
              Expanded(child: child ?? const SizedBox.shrink()),
              if (!onHome) const MiniPlayerBar(),
            ],
          ),
        ),
      ),
      navigatorObservers: [FlutterSmartDialog.observer],
      scrollBehavior: _DesktopScrollBehavior(),
    );
  }

  static ThemeData _theme(ColorScheme scheme) {
    return ThemeData(
      colorScheme: scheme,
      useMaterial3: true,
      visualDensity: VisualDensity.standard,
      splashFactory: PlatformUtils.isDesktop
          ? NoSplash.splashFactory
          : InkSplash.splashFactory,
    );
  }
}

class _DesktopScrollBehavior extends MaterialScrollBehavior {
  /// 与 PiliPlus 相同: 桌面端给可滚动区挂 Scrollbar(默认 hover 行为够用)
  @override
  Widget buildScrollbar(
    BuildContext context,
    Widget child,
    ScrollableDetails details,
  ) {
    if (PlatformUtils.isDesktop) {
      return Scrollbar(controller: details.controller, child: child);
    }
    return child;
  }
}
