import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:auto_route/auto_route.dart';
import 'package:background_downloader/background_downloader.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_displaymode/flutter_displaymode.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/constants/locales.dart';
import 'package:immich_mobile/domain/services/background_worker.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/generated/codegen_loader.g.dart';
import 'package:immich_mobile/models/connection_state.model.dart' as conn;
import 'package:immich_mobile/infrastructure/repositories/network.repository.dart';
import 'package:immich_mobile/pages/common/splash_screen.page.dart';
import 'package:immich_mobile/platform/background_worker_lock_api.g.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/app_life_cycle.provider.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/share_intent_upload.provider.dart';
import 'package:immich_mobile/providers/db.provider.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/providers/debug/network_debug_overlay_visibility.provider.dart';
import 'package:immich_mobile/providers/network/network_monitor.provider.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';
import 'package:immich_mobile/providers/locale_provider.dart';
import 'package:immich_mobile/providers/routes.provider.dart';
import 'package:immich_mobile/providers/theme.provider.dart';
import 'package:immich_mobile/routing/app_navigation_observer.dart';
import 'package:immich_mobile/routing/performance_route_observer.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/services/background.service.dart';
import 'package:immich_mobile/services/deep_link.service.dart';
import 'package:immich_mobile/services/local_notification.service.dart';
import 'package:immich_mobile/theme/dynamic_theme.dart';
import 'package:immich_mobile/theme/theme_data.dart';
import 'package:immich_mobile/utils/bootstrap.dart';
import 'package:immich_mobile/utils/cache/widgets_binding.dart';
import 'package:immich_mobile/utils/certificates_pinning/http_cert_pinning_manager.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:immich_mobile/utils/env_config.dart';
import 'package:immich_mobile/utils/licenses.dart';
import 'package:immich_mobile/utils/migration.dart';
import 'package:immich_mobile/utils/platform_ui.dart';
import 'package:immich_mobile/widgets/debug/network_debug_overlay.widget.dart';
import 'package:immich_mobile/wm_executor.dart';
import 'package:immich_ui/immich_ui.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:logging/logging.dart';
import 'package:timezone/data/latest.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:immich_mobile/services/firebase_performance_wrapper.dart';
import 'package:shared_preferences/shared_preferences.dart' show SharedPreferencesAsync;

void main() async {
  try {
    ImmichWidgetsBinding();
    unawaited(BackgroundWorkerLockService(BackgroundWorkerLockApi()).lock());

    await Firebase.initializeApp();
    await FirebasePerformanceWrapper.initialize();

    await EasyLocalization.ensureInitialized();
    final (isar, drift, logDb) = await Bootstrap.initDB();
    await Bootstrap.initDomain(isar, drift, logDb);
    await initApp();
    // Warm-up isolate pool for worker manager
    await workerManagerPatch.init(dynamicSpawning: true, isolatesCount: max(Platform.numberOfProcessors - 1, 5));
    await migrateDatabaseIfNeeded(isar, drift);
    // const MethodChannel telemetryChannel = MethodChannel('stxphotos/telemetry');
    // await telemetryChannel.invokeMethod('init', ['test']);

    await HttpCertPinningManager.storeDefaultRootCerts();
    await HttpCertPinningManager.ensureInitialized();

    await _startRemoteAccessSession();
    final remoteAccessDependencies = await initHCDevice(
      httpClientProvider: () => NetworkRepository.client,
    );

    final apiservice = ApiService();

    runApp(
      ProviderScope(
        overrides: [
          dbProvider.overrideWithValue(isar),
          isarProvider.overrideWithValue(isar),
          driftProvider.overrideWith(driftOverride(drift)),
          remoteAccessDependenciesProvider.overrideWithValue(remoteAccessDependencies),
          apiServiceProvider.overrideWithValue(apiservice),
        ],
        child: const MainWidget(),
      ),
    );
  } catch (error, stack) {
    runApp(BootstrapErrorWidget(error: error.toString(), stack: stack.toString()));
  }
}

Future<void> _startRemoteAccessSession() async {
  final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
  final sessionId = DateTime.now().microsecondsSinceEpoch.toString();
  await asyncPrefs.setString(remoteCurrentSessionIdKey, sessionId);
}

Future<void> initApp() async {
  final startupLog = Logger("StartupLogger");
  startupLog.info('Starting app with flavor: ${EnvConfig.appFlavor ?? 'unknown'} (env file: ${EnvConfig.envFileName})');

  await initializeDateFormatting();

  if (Platform.isAndroid) {
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

  final certs = await HttpCertPinningManager.loadDefaultRootCertsBytes();

  // Initialize the file downloader
  await FileDownloader().configure(
    // maxConcurrent: 6, maxConcurrentByHost(server):6, maxConcurrentByGroup: 3

    // On Android, if files are larger than 256MB, run in foreground service
    globalConfig: [(Config.holdingQueue, (6, 6, 3)), (Config.runInForegroundIfFileLargerThan, 256)],
    iOSConfig: [(Config.configCertificatePinning, certs)],
    androidConfig: [(Config.configCertificatePinning, certs)],
  );

  await FileDownloader().trackTasksInGroup(kDownloadGroupLivePhoto, markDownloadedComplete: false);

  unawaited(FileDownloader().trackTasks());

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

class ImmichAppState extends ConsumerState<ImmichApp> with WidgetsBindingObserver {
  int? _androidSdkInt;
  StreamSubscription<conn.ConnectionState>? _connectionStateSubscription;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.resumed:
        dPrint(() => "[APP STATE] resumed");
        ref.read(appStateProvider.notifier).handleAppResume();
        unawaited(ref.read(curatorNetworkMonitorProvider).onAppLifecycleResumed());
        break;
      case AppLifecycleState.inactive:
        dPrint(() => "[APP STATE] inactive");
        ref.read(curatorNetworkMonitorProvider).onAppLifecycleBackgrounded();
        ref.read(appStateProvider.notifier).handleAppInactivity();
        break;
      case AppLifecycleState.paused:
        dPrint(() => "[APP STATE] paused");
        ref.read(curatorNetworkMonitorProvider).onAppLifecycleBackgrounded();
        ref.read(appStateProvider.notifier).handleAppPause();
        break;
      case AppLifecycleState.detached:
        dPrint(() => "[APP STATE] detached");
        ref.read(curatorNetworkMonitorProvider).onAppLifecycleBackgrounded();
        ref.read(appStateProvider.notifier).handleAppDetached();
        break;
      case AppLifecycleState.hidden:
        dPrint(() => "[APP STATE] hidden");
        ref.read(curatorNetworkMonitorProvider).onAppLifecycleBackgrounded();
        ref.read(appStateProvider.notifier).handleAppHidden();
        break;
    }
  }

  Future<void> initApp() async {
    WidgetsBinding.instance.addObserver(this);

    // Draw the app from edge to edge
    unawaited(SystemChrome.setEnabledSystemUIMode(SystemUiMode.edgeToEdge));

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
    unawaited(ref.read(hcDeviceEndpointResolverProvider).init());
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(currentRouteNameProvider.notifier).state = SplashScreenRoute.name;
      _syncCuratorNetworkMonitoring(ref.read(authProvider).isAuthenticated);
      // needs to be delayed so that EasyLocalization is working
      if (Store.isBetaTimelineEnabled) {
        ref.read(backgroundServiceProvider).disableService();
        ref.read(backgroundWorkerFgServiceProvider).enable();
        if (Platform.isAndroid) {
          ref
              .read(backgroundWorkerFgServiceProvider)
              .saveNotificationMessage(
                "uploading_media".tr(),
                "backup_background_service_default_notification".tr(),
              );
        }
      } else {
        ref.read(backgroundWorkerFgServiceProvider).disable();
        ref.read(backgroundServiceProvider).resumeServiceIfEnabled();
      }
    });

    ref.read(shareIntentUploadProvider.notifier).init();

    final api = ref.read(apiServiceProvider);
    api.curatorNetworkForceReconnectHandler = () {
      ref.read(curatorNetworkMonitorProvider).forceNetworkChangeHandling();
    };
    _connectionStateSubscription = api.connectionStateChanges.listen((state) {
      if (state.status == conn.ConnectionStatus.connected) {
        ref.read(curatorNetworkMonitorProvider).onConnectionRestored();
      }
      ref.read(curatorNetworkMonitorProvider).callbacks.syncNetworkBanner();
    });
  }

  void _syncCuratorNetworkMonitoring(bool isPhotosAuthenticated) {
    final monitor = ref.read(curatorNetworkMonitorProvider);
    if (isPhotosAuthenticated) {
      monitor.startMonitoring();
    } else {
      monitor.stopMonitoring();
    }
  }

  @override
  void dispose() {
    ref.read(curatorNetworkMonitorProvider).stopMonitoring();
    ref.read(apiServiceProvider).curatorNetworkForceReconnectHandler = null;
    _connectionStateSubscription?.cancel();
    _connectionStateSubscription = null;
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void reassemble() {
    if (kDebugMode) {
      NetworkRepository.init();
    }
    super.reassemble();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(authProvider.select((auth) => auth.isAuthenticated), (previous, isAuthenticated) {
      _syncCuratorNetworkMonitoring(isAuthenticated);
    });

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
        darkTheme: getThemeData(
          colorScheme: immichTheme.dark,
          locale: context.locale,
          ctaColor: immichTheme.ctaColor,
          ctaPressedColor: immichTheme.ctaPressedColor,
          timelineSurface: immichTheme.timelineSurfaceDark,
          chromeSurface: immichTheme.chromeSurfaceDark,
        ),
        theme: getThemeData(
          colorScheme: immichTheme.light,
          locale: context.locale,
          ctaColor: immichTheme.ctaColor,
          ctaPressedColor: immichTheme.ctaPressedColor,
          timelineSurface: immichTheme.timelineSurfaceLight,
          chromeSurface: immichTheme.chromeSurfaceLight,
        ),
        routerConfig: router.config(
          deepLinkBuilder: _deepLinkBuilder,
          navigatorObservers: () => [PerformanceRouteObserver(), AppNavigationObserver(ref: ref)],
        ),
        builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: computeOverlayStyle(context),
          child: ColoredBox(
            color: Theme.of(context).scaffoldBackgroundColor,
            child: ImmichTranslationProvider(
              translations: ImmichTranslations(
                submit: "submit".t(context: context),
                password: "password".t(context: context),
              ),
              child: ImmichThemeProvider(
                colorScheme: context.colorScheme,
                child: Stack(
                  children: [
                    Consumer(
                      builder: (context, ref, _) {
                        final currentRouteName = ref.watch(currentRouteNameProvider);
                        final isSplashScreen = currentRouteName == SplashScreenRoute.name;
                        return isSplashScreen
                            ? child!
                            : SafeArea(
                                bottom: PlatformUiUtils.isAndroidThreeButtonNavigation(context),
                                top: false,
                                child: child!,
                              );
                      },
                    ),
                    Consumer(
                      builder: (context, ref, _) {
                        if (ref.watch(networkDebugOverlayVisibleProvider)) {
                          return const NetworkDebugOverlay();
                        }
                        return const SizedBox.shrink();
                      },
                    ),
                  ],
                ),
              ),
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
