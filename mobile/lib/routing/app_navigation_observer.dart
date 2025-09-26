import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/routes.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/providers/infrastructure/app_update.provider.dart';
import 'package:flutter/widgets.dart' show WidgetsBinding;

class AppNavigationObserver extends AutoRouterObserver {
  /// Riverpod Instance
  final WidgetRef ref;
  bool _updateCheckDone = false;

  AppNavigationObserver({required this.ref});

  @override
  Future<void> didChangeTabRoute(TabPageRoute route, TabPageRoute previousRoute) async {
    Future(() => ref.read(inLockedViewProvider.notifier).state = false);
  }

  @override
  void didPush(Route route, Route? previousRoute) {
    _handleLockedViewState(route, previousRoute);
    _handleDriftLockedFolderState(route, previousRoute);
    Future(() {
      ref.read(currentRouteNameProvider.notifier).state = route.settings.name;
      ref.read(previousRouteNameProvider.notifier).state = previousRoute?.settings.name;
      ref.read(previousRouteDataProvider.notifier).state = previousRoute?.settings;
    });

    // Run app update check once after leaving splash (cold boot)
    final currentName = route.settings.name;
    if (!_updateCheckDone && currentName != SplashScreenRoute.name) {
      _updateCheckDone = true;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        final ctx = ref.read(appRouterProvider).navigatorKey.currentContext;
        if (ctx == null) return;
        ref.read(appUpdateServiceProvider).checkOnStart(context: ctx);
      });
    }
  }

  _handleLockedViewState(Route route, Route? previousRoute) {
    final isInLockedView = ref.read(inLockedViewProvider);
    final isFromLockedViewToDetailView =
        route.settings.name == GalleryViewerRoute.name && previousRoute?.settings.name == LockedRoute.name;

    final isFromDetailViewToInfoPanelView =
        route.settings.name == null && previousRoute?.settings.name == GalleryViewerRoute.name && isInLockedView;

    if (route.settings.name == LockedRoute.name || isFromLockedViewToDetailView || isFromDetailViewToInfoPanelView) {
      Future(() => ref.read(inLockedViewProvider.notifier).state = true);
    } else {
      Future(() => ref.read(inLockedViewProvider.notifier).state = false);
    }
  }

  _handleDriftLockedFolderState(Route route, Route? previousRoute) {
    final isInLockedView = ref.read(inLockedViewProvider);
    final isFromLockedViewToDetailView =
        route.settings.name == AssetViewerRoute.name && previousRoute?.settings.name == DriftLockedFolderRoute.name;

    final isFromDetailViewToInfoPanelView =
        route.settings.name == null && previousRoute?.settings.name == AssetViewerRoute.name && isInLockedView;

    if (route.settings.name == DriftLockedFolderRoute.name ||
        isFromLockedViewToDetailView ||
        isFromDetailViewToInfoPanelView) {
      Future(() => ref.read(inLockedViewProvider.notifier).state = true);
    } else {
      Future(() => ref.read(inLockedViewProvider.notifier).state = false);
    }
  }
}
