import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/album/album.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/scroll_notifier.provider.dart';
import 'package:immich_mobile/providers/multiselect.provider.dart';
import 'package:immich_mobile/providers/search/search_input_focus.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/providers/asset.provider.dart';
import 'package:immich_mobile/providers/haptic_feedback.provider.dart';
import 'package:immich_mobile/providers/tab.provider.dart';
import 'package:immich_mobile/widgets/common/app_bar_dialog/app_bar_drawer.dart';

@RoutePage()
class TabControllerPage extends HookConsumerWidget {
  const TabControllerPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isRefreshingAssets = ref.watch(assetProvider);
    final isRefreshingRemoteAlbums = ref.watch(isRefreshingRemoteAlbumProvider);
    final isScreenLandscape =
        MediaQuery.orientationOf(context) == Orientation.landscape;

    Widget buildIcon({required Widget icon, required bool isProcessing}) {
      if (!isProcessing) return icon;
      return Stack(
        alignment: Alignment.center,
        clipBehavior: Clip.none,
        children: [
          icon,
          Positioned(
            right: -18,
            child: SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                valueColor: AlwaysStoppedAnimation<Color>(
                  context.primaryColor,
                ),
              ),
            ),
          ),
        ],
      );
    }

    void onNavigationSelected(TabsRouter router, int index) {
      // On Photos page menu tapped
      if (router.activeIndex == 0 && index == 0) {
        scrollToTopNotifierProvider.scrollToTop();
      }

      // On Search page tapped
      if (router.activeIndex == 1 && index == 1) {
        ref.read(searchInputFocusProvider).requestFocus();
      }

      ref.read(hapticFeedbackProvider.notifier).selectionClick();
      router.setActiveIndex(index);
      ref.read(tabProvider.notifier).state = TabEnum.values[index];
    }

    final navigationDestinations = [
      NavigationDestination(
        label: 'photos'.tr(),
        icon: const Icon(
          Icons.photo_library_outlined,
        ),
        selectedIcon: buildIcon(
          isProcessing: isRefreshingAssets,
          icon: Icon(
            Icons.photo_library,
            color: context.primaryColor,
          ),
        ),
      ),
      NavigationDestination(
        label: 'search'.tr(),
        icon: const Icon(
          Icons.search_rounded,
        ),
        selectedIcon: Icon(
          Icons.search,
          color: context.primaryColor,
        ),
      ),
      NavigationDestination(
        label: 'albums'.tr(),
        icon: const Icon(
          Icons.photo_album_outlined,
        ),
        selectedIcon: buildIcon(
          isProcessing: isRefreshingRemoteAlbums,
          icon: Icon(
            Icons.photo_album_rounded,
            color: context.primaryColor,
          ),
        ),
      ),
      NavigationDestination(
        label: 'library'.tr(),
        icon: const Icon(
          Icons.space_dashboard_outlined,
        ),
        selectedIcon: buildIcon(
          isProcessing: isRefreshingAssets,
          icon: Icon(
            Icons.space_dashboard_rounded,
            color: context.primaryColor,
          ),
        ),
      ),
    ];

    Widget bottomNavigationBar(TabsRouter tabsRouter) {
      return MediaQuery.removePadding(
        removeTop: true,
        context: context,
        child: NavigationBar(
          selectedIndex: tabsRouter.activeIndex,
          onDestinationSelected: (index) =>
              onNavigationSelected(tabsRouter, index),
          destinations: navigationDestinations,
        ),
      );
    }

    Widget animatedBottomNavigationBar(TabsRouter tabsRouter) {
      final isVisible = ref.watch(scrollNotifierProvider).isVisible;

      return AnimatedSlide(
        duration: const Duration(milliseconds: 200),
        offset: isVisible ? Offset.zero : const Offset(0, 1),
        child: AnimatedOpacity(
          duration: const Duration(milliseconds: 200),
          opacity: isVisible ? 1 : 0,
          child: bottomNavigationBar(tabsRouter),
        ),
      );
    }

    final isVisible = ref.watch(scrollNotifierProvider).isVisible;
    final multiselectEnabled = ref.watch(multiselectProvider);
    return AutoTabsRouter(
      inheritNavigatorObservers: true,
      routes: [
        const PhotosRoute(),
        SearchRoute(),
        const AlbumsRoute(),
        const LibraryRoute(),
      ],
      duration: const Duration(milliseconds: 600),
      transitionBuilder: (context, child, animation) => FadeTransition(
        opacity: animation,
        child: child,
      ),
      builder: (context, child) {
        final tabsRouter = AutoTabsRouter.of(context);
        final heroedChild = HeroControllerScope(
          controller: HeroController(),
          child: child,
        );
        return PopScope(
          canPop: tabsRouter.activeIndex == 0,
          onPopInvokedWithResult: (didPop, _) =>
              !didPop ? tabsRouter.setActiveIndex(0) : null,
          child: Scaffold(
            resizeToAvoidBottomInset: false,
            drawer: const CuratorAppBarDrawer(),
            body: isScreenLandscape
                ? Stack(
                    children: [
                      Positioned.fill(child: heroedChild),
                      Positioned(
                        left: 0,
                        right: 0,
                        bottom: 0,
                        child: AnimatedSlide(
                          offset: isVisible ? Offset.zero : const Offset(0, 1),
                          duration: const Duration(milliseconds: 200),
                          child: Material(
                            elevation: 3,
                            child: animatedBottomNavigationBar(tabsRouter),
                          ),
                        ),
                      ),
                    ],
                  )
                : heroedChild,
            bottomNavigationBar: multiselectEnabled || isScreenLandscape
                ? null
                : bottomNavigationBar(tabsRouter),
          ),
        );
      },
    );
  }
}
