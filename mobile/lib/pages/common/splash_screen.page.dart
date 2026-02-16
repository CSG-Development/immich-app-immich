import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hc_device/api/remote_access.swagger.dart';
import 'package:hc_device/device_discovery.provider.dart';
import 'package:hc_device/providers/device.provider.dart';
import 'package:hc_device/providers/hcdevice.provider.dart';
import 'package:hc_device/providers/remote.provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/constants/onboarding.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/pages/security/lock_flow.dart';
import 'package:immich_mobile/providers/account_manager.provider.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/backup/drift_backup.provider.dart';
import 'package:immich_mobile/providers/device_path_refresh.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/infrastructure/app_update.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/device_path_refresh.service.dart';
import 'package:immich_mobile/services/secure_storage.service.dart';
import 'package:immich_mobile/utils/provider_utils.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:immich_mobile/widgets/common/splash_screen.dart';
import 'package:immich_mobile/widgets/security/local_auth_bottom_sheet.dart';
import 'package:logging/logging.dart';
import 'package:immich_mobile/services/local_auth.service.dart';
import 'package:openapi/api.dart';

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

  Future<void> handleSyncFlow() async {
    final backgroundManager = ref.read(backgroundSyncProvider);

    await backgroundManager.syncLocal(full: true);
    await backgroundManager.syncRemote();
    await backgroundManager.hashAssets();

    if (Store.get(StoreKey.syncAlbums, false)) {
      await backgroundManager.syncLinkedAlbum();
    }
  }

  Future<bool> validateUrl(String? url) async {
    var isServerValid = false;

    if (url?.isNotEmpty != true) {
      return isServerValid;
    }

    final baseUrl = Uri.parse(url!);
    final normalizedBaseUrl =
        '${baseUrl.scheme}://${baseUrl.host}${baseUrl.port != 80 && baseUrl.port != 443 ? ':${baseUrl.port}' : ''}/photos';

    final sanitizedServerUrl = sanitizeUrl(normalizedBaseUrl);
    final normalizedServerUrl = punycodeEncodeUrl(sanitizedServerUrl);

    try {
      await ref.read(authProvider.notifier).validateServerUrl(normalizedServerUrl);

      await ref.read(serverInfoProvider.notifier).getServerInfo();

      ref.read(devicePathRefreshServiceProvider).processAndSavePaths([
        DevicePath(port: baseUrl.port, address: baseUrl.host, type: DevicePathType.public),
      ]);
      isServerValid = true;
    } on ApiException {
      isServerValid = false;
    } on HandshakeException {
      isServerValid = false;
    } catch (_) {
      isServerValid = false;
    }
    return isServerValid;
  }

  Future<bool> login(String email, String password) async {
    invalidateAllApiRepositoryProviders(ref);

    try {
      final result = await ref.read(authProvider.notifier).login(email, password);
      if (result.shouldChangePassword && !result.isAdmin) {
        context.pushRoute(const ChangePasswordRoute());
        return true;
      }
    } catch (_) {
      return false;
    }

    final onboardingWasShown = Store.tryGet(StoreKey.onboardingWasShown) ?? false;

    if (!onboardingWasShown) {
      context.replaceRoute(const CuratorOnboardingRoute());
      return true;
    }

    final isBeta = Store.isBetaTimelineEnabled;
    if (isBeta) {
      await ref.read(galleryPermissionNotifier.notifier).requestGalleryPermission();
      handleSyncFlow();
      ref.read(websocketProvider.notifier).connect();
      context.replaceRoute(const TabShellRoute());
      return true;
    }
    context.replaceRoute(const TabControllerRoute());
    return true;
  }

  Future<void> handleRA({
    required RemoteProvider remoteProvider,
    required DeviceProvider deviceProvider,
    required DeviceDiscoveryController deviceDiscoveryProvider,
    required DevicePathRefreshService devicePathRefreshServiceProvider,
    UserData? userData,
  }) async {
    try {
      final raRefreshToken = userData?.raRefreshToken ?? '';
      final raFavoriteDeviceCertCommonName = userData?.raFavoriteDeviceCertCommonName ?? '';
      final raClientId = userData?.raClientId ?? '';
      final email = userData?.email ?? '';

      deviceProvider.setHost(login: email, deviceID: raFavoriteDeviceCertCommonName);

      if (raRefreshToken.isEmpty || raClientId.isEmpty) {
        return;
      }

      await remoteProvider.setAuthTokenAndRefresh(refreshToken: raRefreshToken, clientId: raClientId);

      if (raFavoriteDeviceCertCommonName.isEmpty) {
        return;
      }

      final devices = await deviceDiscoveryProvider.startRemoteDiscovery();
      final paths = devices
          ?.firstWhere((device) => device.about?.certificateCommonName == raFavoriteDeviceCertCommonName)
          .paths;

      if (paths != null && paths.isNotEmpty) {
        await devicePathRefreshServiceProvider.processAndSavePaths(paths);
      }
    } catch (e) {
      //
    }
  }

  void resumeSession() async {
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
      dynamic systemAccount;
      try {
        systemAccount = await ref.read(accountManagerProvider).getSystemAccount().timeout(const Duration(seconds: 3));
      } on TimeoutException {
        log.warning('getSystemAccount timed out - skipping account auto-login');
        systemAccount = null;
      } catch (error, stackTrace) {
        log.severe('getSystemAccount failed', error, stackTrace);
        systemAccount = null;
      }

      if (systemAccount != null) {
        try {
          var password = await ref
              .read(accountManagerProvider)
              .getSystemAccountPassword(systemAccount)
              .timeout(const Duration(seconds: 3));
          final userData = await ref
              .read(accountManagerProvider)
              .getSystemAccountUserData(systemAccount)
              .timeout(const Duration(seconds: 3));

          final email = userData?.email ?? '';
          password = password ?? '';
          final baseUrl = userData?.baseUrl ?? '';

          if (email.isNotEmpty && password.isNotEmpty && baseUrl.isNotEmpty) {
            final isServerValid = await validateUrl(baseUrl);

            if (isServerValid) {
              final isLoginSuccess = await login(email, password);
              if (isLoginSuccess) {
                handleRA(
                  userData: userData,
                  deviceDiscoveryProvider: ref.read(deviceDiscoveryProvider),
                  remoteProvider: ref.read(remoteProvider),
                  deviceProvider: ref.read(deviceProvider),
                  devicePathRefreshServiceProvider: ref.read(devicePathRefreshServiceProvider),
                );
                return;
              }
            }
          } else {
            log.warning(
              'system account data incomplete - '
              'email/password/baseUrl must be non-empty',
            );
          }
        } on TimeoutException {
          log.warning(
            'timeout while reading password/user data from AccountManager '
            '- skipping account auto-login',
          );
        } catch (error, stackTrace) {
          log.severe('error during system account auto-login', error, stackTrace);
        }
      } else {
        log.info('no system account found - falling back to login route');
      }

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
