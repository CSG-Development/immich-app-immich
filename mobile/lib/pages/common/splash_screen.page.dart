import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/colors.dart';
import 'package:immich_mobile/constants/locales.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/constants/onboarding.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/generated/codegen_loader.g.dart';
import 'package:immich_mobile/generated/translations.g.dart';
import 'package:immich_mobile/pages/security/lock_flow.dart';
import 'package:path/path.dart' as path;
import 'package:path_provider/path_provider.dart';
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
import 'package:immich_mobile/services/local_auth.service.dart';
import 'package:immich_mobile/services/network/endpoint_resolver.dart';
import 'package:immich_mobile/services/secure_storage.service.dart';
import 'package:immich_mobile/theme/color_scheme.dart';
import 'package:immich_mobile/theme/theme_data.dart';
import 'package:immich_mobile/widgets/common/immich_logo.dart';
import 'package:immich_mobile/widgets/common/immich_title_text.dart';
import 'package:immich_mobile/widgets/common/splash_screen.dart';
import 'package:immich_mobile/widgets/security/local_auth_bottom_sheet.dart';
import 'package:logging/logging.dart';
import 'package:url_launcher/url_launcher.dart' show launchUrl, LaunchMode;

class BootstrapErrorWidget extends StatelessWidget {
  final String error;
  final String stack;

  const BootstrapErrorWidget({super.key, required this.error, required this.stack});

  @override
  Widget build(BuildContext _) {
    final immichTheme = defaultColorPreset.themeOfPreset;

    return EasyLocalization(
      supportedLocales: locales.values.toList(),
      path: translationsPath,
      useFallbackTranslations: true,
      fallbackLocale: locales.values.first,
      assetLoader: const CodegenLoader(),
      child: Builder(
        builder: (lCtx) => MaterialApp(
          title: 'Personal Cloud Photos',
          debugShowCheckedModeBanner: true,
          localizationsDelegates: lCtx.localizationDelegates,
          supportedLocales: lCtx.supportedLocales,
          locale: lCtx.locale,
          themeMode: ThemeMode.system,
          darkTheme: getThemeData(colorScheme: immichTheme.dark, locale: lCtx.locale),
          theme: getThemeData(colorScheme: immichTheme.light, locale: lCtx.locale),
          home: Builder(
            builder: (ctx) => Scaffold(
              body: Column(
                children: [
                  const SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: EdgeInsets.symmetric(horizontal: 24, vertical: 16),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [ImmichLogo(size: 48), SizedBox(width: 12), ImmichTitleText(fontSize: 24)],
                      ),
                    ),
                  ),
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: _ErrorCard(error: error, stack: stack),
                    ),
                  ),
                  const Divider(height: 1),
                  const SafeArea(
                    top: false,
                    child: Padding(padding: EdgeInsets.fromLTRB(24, 16, 24, 16), child: _BottomPanel()),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _BottomPanel extends StatefulWidget {
  const _BottomPanel();

  @override
  State<_BottomPanel> createState() => _BottomPanelState();
}

class _BottomPanelState extends State<_BottomPanel> {
  bool _cleared = false;

  Future<void> _clearDatabase() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        title: Text(context.t.reset_sqlite_clear_app_data),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(context.t.reset_sqlite_confirmation),
            const SizedBox(height: 12),
            Text(
              context.t.reset_sqlite_confirmation_note,
              style: Theme.of(context).textTheme.bodySmall?.copyWith(fontWeight: FontWeight.w600),
            ),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.of(dialogCtx).pop(false), child: Text(context.t.cancel)),
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(true),
            child: Text(context.t.confirm, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ),
        ],
      ),
    );

    if (confirmed != true || !mounted) {
      return;
    }

    try {
      final dir = await getApplicationDocumentsDirectory();
      for (final suffix in ['', '-wal', '-shm']) {
        final file = File(path.join(dir.path, 'immich.sqlite$suffix'));
        if (await file.exists()) {
          await file.delete();
        }
      }
    } catch (_) {
      return;
    }

    if (mounted) {
      setState(() => _cleared = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      spacing: 8,
      children: [
        Text(
          _cleared ? context.t.reset_sqlite_done : context.t.scaffold_body_error_unrecoverable,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodySmall,
        ),
        Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            _ActionLink(
              icon: Icons.chat_bubble_outline,
              label: context.t.discord,
              onTap: () => launchUrl(Uri.parse('https://discord.immich.app/'), mode: LaunchMode.externalApplication),
            ),
            _ActionLink(
              icon: Icons.bug_report_outlined,
              label: context.t.profile_drawer_github,
              onTap: () => launchUrl(
                Uri.parse('https://github.com/immich-app/immich/issues'),
                mode: LaunchMode.externalApplication,
              ),
            ),
            if (!_cleared)
              _ActionLink(
                icon: Icons.delete_outline,
                label: context.t.reset_sqlite_clear_app_data,
                onTap: _clearDatabase,
              ),
          ],
        ),
      ],
    );
  }
}

class _ActionLink extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;

  const _ActionLink({required this.icon, required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      borderRadius: const BorderRadius.all(Radius.circular(8)),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 24),
            const SizedBox(height: 4),
            Text(label, style: const TextStyle(fontSize: 12)),
          ],
        ),
      ),
    );
  }
}

class _ErrorCard extends StatelessWidget {
  final String error;
  final String stack;

  const _ErrorCard({required this.error, required this.stack});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;

    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          ColoredBox(
            color: scheme.error,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      context.t.scaffold_body_error_occurred,
                      style: textTheme.titleSmall?.copyWith(color: scheme.onError),
                    ),
                  ),
                  IconButton(
                    tooltip: context.t.copy_error,
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(Icons.copy_outlined, size: 16, color: scheme.onError),
                    onPressed: () => Clipboard.setData(ClipboardData(text: '$error\n\n$stack')),
                  ),
                ],
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Text(error, style: textTheme.bodyMedium),
          ),
          const Divider(height: 1),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(context.t.stacktrace, style: textTheme.labelMedium),
                const SizedBox(height: 4),
                SelectableText(stack, style: textTheme.bodySmall),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

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
      if (!mounted) {
        return Future.value(null);
      }
      return ref
          .read(hcDeviceEndpointResolverProvider)
          .resolveAndActivateWinner(trigger: 'splash_warmup', mode: ResolveMode.foreground)
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
          .resolveAndActivateWinner(trigger: 'splash_warmup', mode: ResolveMode.foreground)
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
    if (!mounted) return;

    final endpoint = Store.tryGet(StoreKey.serverEndpoint);
    final accessToken = Store.tryGet(StoreKey.accessToken);
    final enableBiometric = Store.tryGet(StoreKey.enableBiometric) ?? false;

    final enablePasscodeLock = (await ref.read(secureStorageServiceProvider).read(kSecuredPasscode)) != null;
    final enablePatternLock = (await ref.read(secureStorageServiceProvider).read(kSecuredPattern)) != null;
    if (!mounted) return;

    if (accessToken != null && endpoint != null) {
      final endpointWarmupFuture = _waitForEndpointBeforeStartupRequests();
      final infoProvider = ref.read(serverInfoProvider.notifier);
      final wsProvider = ref.read(websocketProvider.notifier);
      final backgroundManager = ref.read(backgroundSyncProvider);
      final backupProvider = ref.read(driftBackupProvider.notifier);

      unawaited(
        ref
            .read(authProvider.notifier)
            .saveAuthInfo(accessToken: accessToken)
            .then((didRestoreAuth) async {
              if (!mounted) return;
              if (!didRestoreAuth) {
                await _logoutAndRouteToLogin(reason: 'Unable to restore authenticated session');
                return;
              }

              try {
                await endpointWarmupFuture;
                unawaited(wsProvider.connect());
                unawaited(infoProvider.getServerInfo());

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
                      // TODO: Bring back when the soft freeze issue is addressed
                      // backgroundManager.syncCloudIds(),
                    ]);
                  } else {
                    await backgroundManager.hashAssets();
                  }

                  if (Store.get(StoreKey.syncAlbums, false)) {
                    await backgroundManager.syncLinkedAlbum();
                  }
                }
              } catch (e) {
                log.severe('Failed establishing connection to the server: $e');
              }
            }),
      );
    } else {
      await _logoutAndRouteToLogin(reason: 'Missing crucial offline login info');
      return;
    }

    // clean install - change the default of the flag
    // current install not using beta timeline
    if (mounted && context.router.current.name == SplashScreenRoute.name) {
      final needBetaMigration = Store.get(StoreKey.needBetaMigration, false);
      if (needBetaMigration) {
        bool migrate =
            (await showDialog<bool>(
              context: context,
              builder: (ctx) => AlertDialog(
                title: const Text("New Timeline Experience"),
                content: const Text(
                  "The old timeline has been deprecated and will be removed in an upcoming release. Would you like to switch to the new timeline now?",
                ),
                actions: [
                  TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("No")),
                  ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Yes")),
                ],
              ),
            )) ??
            false;
        if (migrate != true) {
          migrate =
              (await showDialog<bool>(
                context: context,
                builder: (ctx) => AlertDialog(
                  title: const Text("Are you sure?"),
                  content: const Text(
                    "If you choose to remain on the old timeline, you will be automatically migrated to the new timeline in an upcoming release. Would you like to switch now?",
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(ctx).pop(false), child: const Text("No")),
                    ElevatedButton(onPressed: () => Navigator.of(ctx).pop(true), child: const Text("Yes")),
                  ],
                ),
              )) ??
              false;
        }
        await Store.put(StoreKey.needBetaMigration, false);
        if (migrate) {
          if (!mounted) return;
          unawaited(context.router.replaceAll([ChangeExperienceRoute(switchingToBeta: true)]));
          return;
        }
      }
    }

    if (!mounted) return;

    final viewedCount = Store.tryGet<int>(StoreKey.onboardingViewedCount) ?? 0;
    if (viewedCount >= kCuratorOnboardingSlidesData.length) {
      await Store.put(StoreKey.onboardingWasShown, true);
      await Store.delete(StoreKey.onboardingViewedCount);
    }
    final onboardingCompleted = Store.tryGet(StoreKey.onboardingWasShown) ?? false;

    Future<void> proceedToMainScreen() async {
      if (!mounted) return;

      if (context.router.current.name != ShareIntentRoute.name) {
        final currentUser = Store.tryGet(StoreKey.currentUser);
        if (currentUser != null && !onboardingCompleted) {
          await context.replaceRoute(const CuratorOnboardingRoute());
          return;
        }
        await context.replaceRoute(Store.isBetaTimelineEnabled ? const TabShellRoute() : const TabControllerRoute());
      }

      if (!mounted || Store.isBetaTimelineEnabled) {
        return;
      }

      final hasPermission = await ref.read(galleryPermissionNotifier.notifier).hasPermission;
      if (!mounted) return;
      if (hasPermission) {
        await ref.read(backupProvider.notifier).resumeBackup();
      }
    }

    final canAuthenticate = (await ref.read(localAuthServiceProvider).getStatus()).canAuthenticate;
    if (!mounted) return;

    if (enableBiometric && canAuthenticate) {
      await showLocalAuthBottomSheet(context: context, onSuccess: proceedToMainScreen);
    } else if (enablePasscodeLock) {
      await context.pushRoute(PasscodeLockRoute(flow: LockFlow.validate, onSuccess: proceedToMainScreen));
    } else if (enablePatternLock) {
      await context.pushRoute(PatternLockRoute(flow: LockFlow.validate, onSuccess: proceedToMainScreen));
    } else {
      await proceedToMainScreen();
    }
  }

  Future<void> _resumeBackup(DriftBackupNotifier notifier) async {
    final isEnableBackup = Store.get(StoreKey.enableBackup, false);

    if (!isEnableBackup) {
      return;
    }

    final currentUser = Store.tryGet(StoreKey.currentUser);
    if (currentUser == null) {
      return;
    }

    unawaited(notifier.startForegroundBackup(currentUser.id));
  }

  Future<void> _logoutAndRouteToLogin({required String reason}) async {
    log.severe('$reason - logging out completely');
    await ref.read(authProvider.notifier).logout();
    if (mounted) {
      await context.replaceRoute(const LoginRoute());
    }
  }

  @override
  Widget build(BuildContext context) {
    return const SplashScreen();
  }
}
