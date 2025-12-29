import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/constants/onboarding.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/backup/drift_backup.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/local_auth.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:logging/logging.dart';
import 'package:immich_mobile/services/local_auth.service.dart';

@RoutePage()
class SplashScreenPage extends StatefulHookConsumerWidget {
  const SplashScreenPage({super.key});

  @override
  SplashScreenPageState createState() => SplashScreenPageState();
}

class SplashScreenPageState extends ConsumerState<SplashScreenPage> {
  final log = Logger("SplashScreenPage");

  @override
  void initState() {
    super.initState();
    ref
        .read(apiServiceProvider)
        .setOpenApiServiceEndpoint()
        .then(logConnectionInfo)
        .whenComplete(() => resumeSession());
  }

  void logConnectionInfo(String? endpoint) {
    if (endpoint == null) {
      return;
    }

    log.info("Resuming session at $endpoint");
  }

  void resumeSession() async {
    if (!mounted) return;
    // final serverUrl = Store.tryGet(StoreKey.serverUrl);
    final endpoint = Store.tryGet(StoreKey.serverEndpoint);
    final accessToken = Store.tryGet(StoreKey.accessToken);
    final enableBiometric = Store.tryGet(StoreKey.enableBiometric) ?? false;

    if (accessToken != null &&
        // serverUrl != null &&
        endpoint != null) {
      final infoProvider = ref.read(serverInfoProvider.notifier);
      final wsProvider = ref.read(websocketProvider.notifier);
      final backgroundManager = ref.read(backgroundSyncProvider);
      final backupProvider = ref.read(driftBackupProvider.notifier);

      ref.read(authProvider.notifier).saveAuthInfo(accessToken: accessToken).then(
        (_) async {
          try {
            wsProvider.connect();
            infoProvider.getServerInfo();

            if (Store.isBetaTimelineEnabled) {
              bool syncSuccess = false;
              await Future.wait([
                backgroundManager.syncLocal(full: true),
                backgroundManager.syncRemote().then((success) => syncSuccess = success),
              ]);

              if (syncSuccess) {
                await Future.wait([
                  backgroundManager.hashAssets().then((_) {
                    _resumeBackup(backupProvider);
                  }),
                  _resumeBackup(backupProvider),
                ]);
              } else {
                backupProvider.updateError(BackupError.syncFailed);
                await backgroundManager.hashAssets();
              }

              if (Store.get(StoreKey.syncAlbums, false)) {
                await backgroundManager.syncLinkedAlbum();
              }
            }
          } catch (e) {
            log.severe('Failed establishing connection to the server: $e');
          }
        },
        onError: (exception) => {
          log.severe('Failed to update auth info with access token: $accessToken'),
          ref.read(authProvider.notifier).logout(),
          if (mounted) context.replaceRoute(const LoginRoute()),
        },
      );
    } else {
      log.severe('Missing crucial offline login info - Logging out completely');
      ref.read(authProvider.notifier).logout();
      if (mounted) context.replaceRoute(const LoginRoute());
      return;
    }

    // clean install - change the default of the flag
    // current install not using beta timeline
    if (mounted && context.router.current.name == SplashScreenRoute.name) {
      final needBetaMigration = Store.get(StoreKey.needBetaMigration, false);
      if (needBetaMigration) {
        await Store.put(StoreKey.needBetaMigration, false);
        if (!mounted) return;
        context.router.replaceAll([ChangeExperienceRoute(switchingToBeta: true)]);
        return;
      }
    }

    final viewedCount = Store.tryGet<int>(StoreKey.onboardingViewedCount) ?? 0;
    if (viewedCount >= kCuratorOnboardingSlidesData.length) {
      await Store.put(StoreKey.onboardingWasShown, true);
      await Store.delete(StoreKey.onboardingViewedCount);
    }
    final onboardingCompleted = Store.tryGet(StoreKey.onboardingWasShown) ?? false;

    void proceedToMainScreen() async {
      if (context.router.current.name != ShareIntentRoute.name) {
        final accessToken = Store.tryGet(StoreKey.accessToken);
        if (accessToken != null) {
          if (!onboardingCompleted) {
            context.replaceRoute(const CuratorOnboardingRoute());
            return;
          }
        }
        context.replaceRoute(Store.isBetaTimelineEnabled ? const TabShellRoute() : const TabControllerRoute());
      }
    }

    final canAuthenticate = (await ref.read(localAuthServiceProvider).getStatus()).canAuthenticate;
    if (enableBiometric && canAuthenticate) {
      // Try biometric authentication up to 3 times
      int attempts = 0;
      bool authSuccess = false;
      
      while (attempts < 3 && !authSuccess) {
        authSuccess = await ref.read(localAuthProvider.notifier).authenticate(context, null);
        if (authSuccess) {
          proceedToMainScreen();
          return;
        }
        attempts++;
      }
      
      // If all attempts failed, logout user
      if (!authSuccess) {
        ref.read(authProvider.notifier).logout();
        if (mounted) context.replaceRoute(const LoginRoute());
        return;
      }
    } else {
      proceedToMainScreen();
    }

    if (Store.isBetaTimelineEnabled) {
      return;
    }

    if (!mounted) return;
    final hasPermission = await ref.read(galleryPermissionNotifier.notifier).hasPermission;
    if (hasPermission) {
      // Resume backup (if enable) then navigate
      if (!mounted) return;
      ref.read(backupProvider.notifier).resumeBackup();
    }
  }

  Future<void> _resumeBackup(DriftBackupNotifier notifier) async {
    final isEnableBackup = Store.get(StoreKey.enableBackup, false);

    if (isEnableBackup) {
      final currentUser = Store.tryGet(StoreKey.currentUser);
      if (currentUser != null) {
        notifier.handleBackupResume(currentUser.id);
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    final backgroundColor = isAndroid
        ? const Color(0xFF19181E)
        : Theme.of(context).colorScheme.surface;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _splashOverlayStyle(context),
      child: Scaffold(
        backgroundColor: backgroundColor,
        body: const SizedBox.expand(
          child: Image(
            image: AssetImage('assets/immich-splash.png'),
            filterQuality: FilterQuality.medium,
            fit: BoxFit.fitHeight,
          ),
        ),
      ),
    );
  }
}

SystemUiOverlayStyle _splashOverlayStyle(BuildContext context) {
  // Splash is dark; prefer light icons. Keep gesture nav edge-to-edge.
  Color navColor = Colors.transparent;
  Brightness iconBrightness = Brightness.light;

  if (Platform.isAndroid) {
    // Force dark nav bar on splash for all Android modes
    navColor = const Color(0xFF000000);
  }

  return SystemUiOverlayStyle(
    systemNavigationBarColor: navColor,
    systemNavigationBarIconBrightness: iconBrightness,
  );
}
