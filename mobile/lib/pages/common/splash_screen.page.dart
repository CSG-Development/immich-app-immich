import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/constants/onboarding.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/pages/security/lock_flow.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/backup/drift_backup.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/infrastructure/app_update.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/secure_storage.service.dart';
import 'package:immich_mobile/services/network/endpoint_resolver.dart';
import 'package:immich_mobile/widgets/common/splash_screen.dart';
import 'package:immich_mobile/widgets/security/local_auth_bottom_sheet.dart';
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
    unawaited(_bootstrapSession());
  }

  Future<void> _bootstrapSession() async {
    // Do not block splash on endpoint probing.
    unawaited(_warmupEndpointResolution());
    await resumeSession();
  }

  Future<void> _waitForEndpointBeforeStartupRequests() async {
    // Keep startup responsive: wait briefly for endpoint settle, then continue.
    Future<String?> resolve() {
      return ref
          .read(hcDeviceEndpointResolverProvider)
          .resolveAndActivateWinner(
            trigger: 'splash_warmup',
            mode: ResolveMode.foreground,
          )
          .timeout(const Duration(seconds: 4));
    }

    try {
      await resolve();
      return;
    } catch (error) {
      log.warning('Startup endpoint wait attempt failed, retrying once: $error');
    }

    try {
      await Future<void>.delayed(const Duration(milliseconds: 400));
      await resolve();
    } catch (error) {
      log.warning('Startup endpoint wait failed after retry, continuing: $error');
    }
  }

  Future<void> _warmupEndpointResolution() async {
    try {
      await ref
          .read(hcDeviceEndpointResolverProvider)
          .resolveAndActivateWinner(
            trigger: 'splash_warmup',
            mode: ResolveMode.foreground,
          )
          .timeout(const Duration(seconds: 8));
      if (!mounted) {
        return;
      }
      final endpoint = ref.read(apiServiceProvider).apiClient.basePath;
      logConnectionInfo(endpoint);
    } catch (error) {
      // Startup should continue if path probing times out/fails.
      if (!mounted) {
        return;
      }
      log.warning('Startup endpoint warmup failed (continuing): $error');
    }
  }

  void logConnectionInfo(String? endpoint) {
    if (endpoint == null) {
      return;
    }

    log.info("Resuming session at $endpoint");
  }

  Future<void> resumeSession() async {
    if (!mounted) return;

    await ref.read(appUpdateServiceProvider).checkOnStart(context: context);

    // final serverUrl = Store.tryGet(StoreKey.serverUrl);
    final endpoint = Store.tryGet(StoreKey.serverEndpoint);
    final accessToken = Store.tryGet(StoreKey.accessToken);
    final enableBiometric = Store.tryGet(StoreKey.enableBiometric) ?? false;

    final enablePasscodeLock = (await ref.read(secureStorageServiceProvider).read(kSecuredPasscode)) != null;
    final enablePatternLock = (await ref.read(secureStorageServiceProvider).read(kSecuredPattern)) != null;

    if (accessToken != null &&
        // serverUrl != null &&
        endpoint != null) {
      final endpointWarmupFuture = _waitForEndpointBeforeStartupRequests();
      final infoProvider = ref.read(serverInfoProvider.notifier);
      final wsProvider = ref.read(websocketProvider.notifier);
      final backgroundManager = ref.read(backgroundSyncProvider);
      final backupProvider = ref.read(driftBackupProvider.notifier);

      ref.read(authProvider.notifier).saveAuthInfo(accessToken: accessToken).then(
        (_) async {
          try {
            await endpointWarmupFuture;
            wsProvider.connect();
            infoProvider.getServerInfo();

            if (Store.isBetaTimelineEnabled) {
              bool syncSuccess = false;
              await Future.wait([
                backgroundManager.syncLocal(full: true),
                backgroundManager.syncRemote().then((success) => syncSuccess = success),
              ]);

              if (!syncSuccess) {
                await Future<void>.delayed(const Duration(seconds: 2));
                syncSuccess = await backgroundManager.syncRemote();
              }

              if (syncSuccess) {
                backupProvider.updateError(BackupError.none);
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

      if (Store.isBetaTimelineEnabled) {
        return;
      }

      final hasPermission = await ref.read(galleryPermissionNotifier.notifier).hasPermission;
      if (hasPermission) {
        // Resume backup (if enable) then navigate
        ref.read(backupProvider.notifier).resumeBackup();
      }
    }

    final canAuthenticate = (await ref.read(localAuthServiceProvider).getStatus()).canAuthenticate;
    if (enableBiometric && canAuthenticate) {
      await showLocalAuthBottomSheet(context: context, onSuccess: proceedToMainScreen);
    } else if (enablePasscodeLock) {
      await context.pushRoute(PasscodeLockRoute(flow: LockFlow.validate, onSuccess: proceedToMainScreen));
    } else if (enablePatternLock) {
      await context.pushRoute(PatternLockRoute(flow: LockFlow.validate, onSuccess: proceedToMainScreen));
    } else {
      proceedToMainScreen();
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
    return const SplashScreen();
  }
}
