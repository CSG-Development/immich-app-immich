import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/secure_store.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/secure_store.entity.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/local_auth.provider.dart';
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
        .read(authProvider.notifier)
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
    final serverUrl = Store.tryGet(StoreKey.serverUrl);
    final endpoint = Store.tryGet(StoreKey.serverEndpoint);
    final accessToken = SecureStore.tryGet(SecureStoreKey.accessToken);
    final enableBiometric = Store.tryGet(StoreKey.enableBiometric) ?? false;

    bool isAuthSuccess = false;

    if (accessToken != null && serverUrl != null && endpoint != null) {
      try {
        isAuthSuccess = await ref.read(authProvider.notifier).saveAuthInfo(
              accessToken: accessToken,
            );
      } catch (error, stackTrace) {
        log.severe(
          'Cannot set success login info',
          error,
          stackTrace,
        );
      }
    } else {
      isAuthSuccess = false;
      log.severe(
        'Missing authentication, server, or endpoint info from the local store',
      );
    }

    if (!isAuthSuccess) {
      log.severe(
        'Unable to login using offline or online methods - Logging out completely',
      );
      ref.read(authProvider.notifier).logout();
      context.replaceRoute(const LoginRoute());
      return;
    }

    void proceedToMainScreen() async {
      if (context.router.current.name != ShareIntentRoute.name) {
        context.replaceRoute(const TabControllerRoute());
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
        context.replaceRoute(const LoginRoute());
        return;
      }
    } else {
      proceedToMainScreen();
    }

    final hasPermission =
        await ref.read(galleryPermissionNotifier.notifier).hasPermission;
    if (hasPermission) {
      // Resume backup (if enable) then navigate
      ref.watch(backupProvider.notifier).resumeBackup();
    }
  }

  @override
  Widget build(BuildContext context) {
    return const Scaffold(
      backgroundColor: Color(0xFF05070E),
      body: SizedBox.expand(
        child: Image(
          image: AssetImage('assets/immich-splash.png'),
          filterQuality: FilterQuality.medium,
          fit: BoxFit.contain,
        ),
      ),
    );
  }
}
