import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/constants/locales.dart';
import 'package:immich_mobile/domain/services/background_worker.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/generated/codegen_loader.g.dart';
import 'package:immich_mobile/platform/background_worker_lock_api.g.dart';
import 'package:immich_mobile/providers/app_life_cycle.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/share_intent_upload.provider.dart';
import 'package:immich_mobile/providers/db.provider.dart';
import 'package:immich_mobile/providers/endpoint_recovery.provider.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/network_change_listener.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/providers/locale_provider.dart';
import 'package:immich_mobile/providers/routes.provider.dart';
import 'package:immich_mobile/providers/theme.provider.dart';
import 'package:immich_mobile/routing/app_navigation_observer.dart';
import 'package:immich_mobile/routing/performance_route_observer.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/background.service.dart';
import 'package:immich_mobile/services/deep_link.service.dart';
import 'package:immich_mobile/services/local_notification.service.dart';
import 'package:immich_mobile/theme/dynamic_theme.dart';
import 'package:immich_mobile/theme/theme_data.dart';
import 'package:immich_mobile/utils/bootstrap.dart';
import 'package:immich_mobile/utils/cache/widgets_binding.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:immich_mobile/utils/http_ssl_options.dart';
import 'package:immich_mobile/utils/licenses.dart';
import 'package:immich_mobile/utils/migration.dart';
import 'package:immich_mobile/utils/platform_ui.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:timezone/data/latest.dart';
import 'package:worker_manager/worker_manager.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:immich_mobile/services/firebase_performance_wrapper.dart';

import 'package:homecloud_frontend/homecloud_frontend.dart';

void main() async {
  ImmichWidgetsBinding();
  unawaited(BackgroundWorkerLockService(BackgroundWorkerLockApi()).lock());

  await Firebase.initializeApp();
  await FirebasePerformanceWrapper.initialize();

  final (isar, drift, logDb) = await Bootstrap.initDB();
  await Bootstrap.initDomain(isar, drift, logDb);
  await initApp();
  // Warm-up isolate pool for worker manager
  await workerManager.init(dynamicSpawning: true);
  await migrateDatabaseIfNeeded(isar, drift);
  HttpSSLOptions.apply();

  // const MethodChannel telemetryChannel = MethodChannel('stxphotos/telemetry');
  // await telemetryChannel.invokeMethod('init', ['test']);

  final remoteAccessDependencies = await initHCDevice();

  runApp(
    ProviderScope(
      overrides: [
        dbProvider.overrideWithValue(isar),
        isarProvider.overrideWithValue(isar),
        driftProvider.overrideWith(driftOverride(drift)),
        remoteAccessDependenciesProvider.overrideWithValue(remoteAccessDependencies),
      ],
      child: const MainWidget(),
    ),
  );
}

Future<void> initApp() async {
  await EasyLocalization.ensureInitialized();
  await initializeDateFormatting();

  if (kReleaseMode && Platform.isAndroid) {
    try {
      await FlutterDisplayMode.setHighRefreshRate();
      dPrint(() => "Enabled high refresh mode");
    } catch (e) {
      dPrint(() => "Error setting high refresh rate: $e");
    }
  }

  await DynamicTheme.fetchSystemPalette();

  final log = Logger("PersonalCloudPhotosErrorLogger");

  FlutterError.onError = (details) {
    FlutterError.presentError(details);
    log.severe(
      'FlutterError - Catch all',
      "${details.toString()}\nException: ${details.exception}\nLibrary: ${details.library}\nContext: ${details.context}",
      details.stack,
    );
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    log.severe('PlatformDispatcher - Catch all', error, stack);
    return true;
  };

  initializeTimeZones();

  // Initialize the file downloader
  await FileDownloader().configure(
    // maxConcurrent: 6, maxConcurrentByHost(server):6, maxConcurrentByGroup: 3

    // On Android, if files are larger than 256MB, run in foreground service
    globalConfig: [(Config.holdingQueue, (6, 6, 3)), (Config.runInForegroundIfFileLargerThan, 256)],
  );

  await FileDownloader().trackTasksInGroup(kDownloadGroupLivePhoto, markDownloadedComplete: false);

  await FileDownloader().trackTasks();

  LicenseRegistry.addLicense(() async* {
    for (final license in nonPubLicenses.entries) {
      yield LicenseEntryWithLineBreaks([license.key], license.value);
    }
  });
}

class ImmichApp extends ConsumerStatefulWidget {
  const ImmichApp({super.key});

  @override
  ImmichAppState createState() => ImmichAppState();
}

class ImmichAppState extends ConsumerState<ImmichApp>
    with WidgetsBindingObserver {
  int? _androidSdkInt;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        dPrint(() => "[APP STATE] resumed");
        ref.read(appStateProvider.notifier).handleAppResume();
        break;
      case AppLifecycleState.inactive:
        dPrint(() => "[APP STATE] inactive");
        ref.read(appStateProvider.notifier).handleAppInactivity();
        break;
      case AppLifecycleState.paused:
        dPrint(() => "[APP STATE] paused");
        ref.read(appStateProvider.notifier).handleAppPause();
        break;
      case AppLifecycleState.detached:
        dPrint(() => "[APP STATE] detached");
        ref.read(appStateProvider.notifier).handleAppDetached();
        break;
      case AppLifecycleState.hidden:
        dPrint(() => "[APP STATE] hidden");
        ref.read(appStateProvider.notifier).handleAppHidden();
        break;
    }
  }

  Future<void> initApp() async {
    WidgetsBinding.instance.addObserver(this);

    // Draw the app from edge to edge
    SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge);

    // Sets the navigation bar color
    SystemUiOverlayStyle overlayStyle = const SystemUiOverlayStyle(systemNavigationBarColor: Colors.transparent);
    if (Platform.isAndroid) {
      // Android 8 does not support transparent app bars
      final info = await DeviceInfoPlugin().androidInfo;
      _androidSdkInt = info.version.sdkInt;
      if (info.version.sdkInt <= 26) {
        overlayStyle = context.isDarkTheme ? SystemUiOverlayStyle.dark : SystemUiOverlayStyle.light;
      }
    }
    SystemChrome.setSystemUIOverlayStyle(overlayStyle);
    await ref.read(localNotificationService).setup();
  }

  Future<DeepLink> _deepLinkBuilder(PlatformDeepLink deepLink) async {
    final deepLinkHandler = ref.read(deepLinkServiceProvider);
    final currentRouteName = ref.read(currentRouteNameProvider.notifier).state;

    final isColdStart = currentRouteName == null || currentRouteName == SplashScreenRoute.name;

    if (deepLink.uri.scheme == "immich") {
      final proposedRoute = await deepLinkHandler.handleScheme(deepLink, ref, isColdStart);

      return proposedRoute;
    }

    if (deepLink.uri.host == "my.immich.app") {
      final proposedRoute = await deepLinkHandler.handleMyImmichApp(deepLink, ref, isColdStart);

      return proposedRoute;
    }

    return DeepLink.path(deepLink.path);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    Intl.defaultLocale = context.locale.toLanguageTag();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      configureFileDownloaderNotifications();
    });
  }

  @override
  initState() {
    super.initState();
    initApp().then((_) => dPrint(() => "App Init Completed"));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      // needs to be delayed so that EasyLocalization is working
      if (Store.isBetaTimelineEnabled) {
        ref.read(backgroundServiceProvider).disableService();
        ref.read(backgroundWorkerFgServiceProvider).enable();
      } else {
        ref.read(backgroundWorkerFgServiceProvider).disable();
        ref.read(backgroundServiceProvider).resumeServiceIfEnabled();
      }
    });

    ref.read(shareIntentUploadProvider.notifier).init();

    // Initialize endpoint recovery service to start listening to connection state changes
    ref.read(endpointRecoveryServiceProvider);
    
    // Initialize network change listener to handle WiFi connectivity changes
    ref.read(networkChangeListenerServiceProvider).startListening();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final router = ref.watch(appRouterProvider);
    final immichTheme = ref.watch(immichThemeProvider);

    return ProviderScope(
      overrides: [localeProvider.overrideWithValue(context.locale)],
      child: MaterialApp.router(
        title: 'Personal Cloud Photos',
        debugShowCheckedModeBanner: true,
        localizationsDelegates: context.localizationDelegates,
        supportedLocales: context.supportedLocales,
        locale: context.locale,
        themeMode: ref.watch(immichThemeModeProvider),
        // routeInformationParser: router.defaultRouteParser(),
        darkTheme: getThemeData(colorScheme: immichTheme.dark, locale: context.locale),
        theme: getThemeData(colorScheme: immichTheme.light, locale: context.locale),
        routerConfig: router.config(
          deepLinkBuilder: _deepLinkBuilder,
          navigatorObservers: () => [
            PerformanceRouteObserver(),
            AppNavigationObserver(ref: ref),
            ],
        ),
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: computeOverlayStyle(context),
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: SafeArea(
              bottom: PlatformUiUtils.isAndroidThreeButtonNavigation(context),
              top: false,
              child: child!,
            ),
          ),
        ),
      ),
    );
  }
}

extension _SystemUiOverlayExt on ImmichAppState {
  SystemUiOverlayStyle computeOverlayStyle(BuildContext context) {
    final isDark = context.isDarkTheme;
    final colorScheme = Theme.of(context).colorScheme;

    Color navColor = Colors.transparent;
    Brightness iconBrightness = isDark ? Brightness.light : Brightness.dark;

    if (Platform.isAndroid) {
      final isThreeButton = PlatformUiUtils.isAndroidThreeButtonNavigation(context);
      final sdk = _androidSdkInt ?? 0;

      if (sdk <= 26) {
        // Android 8 and below: avoid transparency; use solid contrasting color
        navColor = isDark ? const Color(0xFF000000) : const Color(0xFFFFFFFF);
      } else if (isThreeButton) {
        // For 3-button nav, paint bar to match theme surface
        navColor = colorScheme.surface;
      } else {
        // Gesture nav: keep transparent for edge-to-edge
        navColor = Colors.transparent;
      }
    }

    return SystemUiOverlayStyle(
      systemNavigationBarColor: navColor,
      systemNavigationBarIconBrightness: iconBrightness,
      // Keep status bar behavior as-is; Material handles status bar insets
    );
  }
}

class MainWidget extends StatelessWidget {
  const MainWidget({super.key});

  @override
  Widget build(BuildContext context) {
    return EasyLocalization(
      supportedLocales: locales.values.toList(),
      path: translationsPath,
      useFallbackTranslations: true,
      fallbackLocale: locales.values.first,
      assetLoader: const CodegenLoader(),
      child: const ImmichApp(),
    );
  }
}
