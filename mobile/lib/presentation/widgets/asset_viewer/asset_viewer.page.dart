import 'dart:async';
import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/album/album.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/events.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/domain/utils/event_stream.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/platform_extensions.dart';
import 'package:immich_mobile/extensions/scroll_extensions.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/download_status_floating_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/airplay_timeline_playback.helper.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_page.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_preloader.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/asset_stack.provider.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/viewer_bottom_app_bar.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/viewer_top_app_bar.widget.dart';
import 'package:immich_mobile/providers/airplay.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/cast.provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset_viewer/viewer_scope.provider.dart';
import 'package:immich_mobile/providers/infrastructure/current_album.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/utils/system_ui.utils.dart';
import 'package:immich_mobile/widgets/photo_view/photo_view.dart';

@RoutePage()
class AssetViewerPage extends StatelessWidget {
  final int initialIndex;
  final TimelineService timelineService;
  final int? heroOffset;
  final bool closeViewerWhenAssetLeavesTimeline;
  final RemoteAlbum? currentAlbum;

  const AssetViewerPage({
    super.key,
    required this.initialIndex,
    required this.timelineService,
    this.heroOffset,
    this.closeViewerWhenAssetLeavesTimeline = false,
    this.currentAlbum,
  });

  @override
  Widget build(BuildContext context) {
    // This is necessary to ensure that the timeline service is available
    // since the Timeline and AssetViewer are on different routes / Widget subtrees.
    return ProviderScope(
      overrides: [
        timelineServiceProvider.overrideWithValue(timelineService),
        assetViewerPlacesExitProvider.overrideWithValue(closeViewerWhenAssetLeavesTimeline),
        currentRemoteAlbumScopedProvider.overrideWithValue(currentAlbum),
      ],
      child: AssetViewer(initialIndex: initialIndex, heroOffset: heroOffset),
    );
  }
}

class AssetViewer extends ConsumerStatefulWidget {
  final int initialIndex;
  final int? heroOffset;

  const AssetViewer({super.key, required this.initialIndex, this.heroOffset});

  @override
  ConsumerState createState() => _AssetViewerState();

  static void setAsset(WidgetRef ref, BaseAsset asset) {
    ref.read(assetViewerProvider.notifier).reset();

    // Hide controls by default for videos
    if (asset.isVideo) {
      ref.read(assetViewerProvider.notifier).setControls(false);
    }

    _setAsset(ref, asset);
  }

  static void _setAsset(WidgetRef ref, BaseAsset asset) {
    ref.read(assetViewerProvider.notifier).setAsset(asset);
  }
}

class _AssetViewerState extends ConsumerState<AssetViewer> {
  static const _viewerOverlayStyle = SystemUiOverlayStyle(
    statusBarIconBrightness: Brightness.light,
    statusBarBrightness: Brightness.dark,
    systemNavigationBarIconBrightness: Brightness.light,
  );

  late final _heroOffset = widget.heroOffset ?? TabsRouterScope.of(context)?.controller.activeIndex ?? 0;
  late final _pageController = PageController(initialPage: widget.initialIndex);
  late final _preloader = AssetPreloader(timelineService: ref.read(timelineServiceProvider), mounted: () => mounted);

  late int _currentPage = widget.initialIndex;
  late int _totalAssets = ref.read(timelineServiceProvider).totalAssets;

  StreamSubscription? _reloadSubscription;
  KeepAliveLink? _stackChildrenKeepAlive;

  BaseAsset? _fallbackAsset;
  bool _didShowMovedPlaceToast = false;

  /// Hero tag of an asset the viewer intentionally navigated away from (archive,
  /// lock, delete, etc.). Prevents timeline reload from jumping back to it.
  String? _dismissedHeroTag;

  /// Guards against stale async asset loads reverting the viewer after dismissal.
  int _assetChangeGeneration = 0;

  bool get _isPlacesScopedViewer => ref.read(assetViewerPlacesExitProvider);

  int get _itemCount => _totalAssets == 0 && _fallbackAsset != null ? 1 : _totalAssets;

  void _showMovedPlaceNotice() {
    if (_didShowMovedPlaceToast || !mounted) {
      return;
    }
    _didShowMovedPlaceToast = true;
    ImmichToast.show(context: context, msg: "asset_moved_to_another_place".tr(), toastType: ToastType.info);
  }

  void _exitViewerAfterPlacesLocationEdit() {
    if (!mounted) {
      return;
    }
    _showMovedPlaceNotice();
    context.maybePop();
  }

  void _onTapNavigate(int direction) {
    final page = _pageController.page?.toInt();
    if (page == null) {
      return;
    }
    final target = page + direction;
    final maxPage = _totalAssets - 1;
    if (target >= 0 && target <= maxPage) {
      _pageController.jumpToPage(target);
      _onAssetChanged(target);
    }
  }

  @override
  void initState() {
    super.initState();

    _totalAssets = ref.read(timelineServiceProvider).totalAssets;

    final asset = ref.read(assetViewerProvider).currentAsset;
    assert(asset != null, "Current asset should not be null when opening the AssetViewer");
    if (asset != null) {
      _stackChildrenKeepAlive = ref.read(stackChildrenNotifier(asset).notifier).ref.keepAlive();
    }

    _reloadSubscription = EventStream.shared.listen(_onEvent);

    WidgetsBinding.instance.addPostFrameCallback(_onAssetInit);

    final assetViewer = ref.read(assetViewerProvider);
    _setSystemUIMode(assetViewer.showingControls, assetViewer.showingDetails);
  }

  @override
  void dispose() {
    _pageController.dispose();
    _preloader.dispose();
    _reloadSubscription?.cancel();
    _stackChildrenKeepAlive?.close();

    unawaited(restoreEdgeToEdge());

    super.dispose();
  }

  // The normal onPageChange callback listens to OnScrollUpdate events, and will
  // round the current page and update whenever that value changes. In practise,
  // this means that the page will change when swiped half way, and may flip
  // whilst dragging.
  //
  // Changing the page at the end of a scroll should be more robust, and allow
  // the page to be dragged more than half way whilst keeping the current video
  // playing, and preventing the video on the next page from becoming ready
  // unnecessarily.
  bool _onScrollEnd(ScrollEndNotification notification) {
    if (notification.depth != 0) {
      return false;
    }

    final page = _pageController.page?.round();
    if (page != null && page != _currentPage) {
      _onAssetChanged(page);
    }
    return false;
  }

  void _onAssetInit(Duration timeStamp) {
    _preloader.preload(widget.initialIndex, context.sizeData);
    _handleCasting();
  }

  Future<void> _onAssetChanged(int index) async {
    final generation = ++_assetChangeGeneration;
    _currentPage = index;

    final asset = await ref.read(timelineServiceProvider).getAssetAsync(index);
    if (!mounted || generation != _assetChangeGeneration || asset == null) {
      return;
    }

    final dismissedHeroTag = _dismissedHeroTag;
    if (dismissedHeroTag != null && asset.heroTag == dismissedHeroTag) {
      return;
    }

    if (!(ModalRoute.of(context)?.isActive ?? true)) {
      return;
    }

    _fallbackAsset = null;
    _didShowMovedPlaceToast = false;
    AssetViewer._setAsset(ref, asset);
    _preloader.preload(index, context.sizeData);
    if (AirplayTimelinePlayback.isSupported && ref.read(airplayProvider)) {
      unawaited(
        AirplayTimelinePlayback.prefetchNeighbors(
          index: index,
          timelineService: ref.read(timelineServiceProvider),
          ref: ref,
        ),
      );
    }
    _handleCasting();
    _stackChildrenKeepAlive?.close();
    _stackChildrenKeepAlive = ref.read(stackChildrenNotifier(asset).notifier).ref.keepAlive();
  }

  void _handleCasting() {
    if (!ref.read(castProvider).isCasting) {
      return;
    }
    final asset = ref.read(assetViewerProvider).currentAsset;
    if (asset == null) {
      return;
    }

    if (asset is RemoteAsset) {
      context.scaffoldMessenger.hideCurrentSnackBar();
      ref.read(castProvider.notifier).loadMedia(asset, false);
    } else {
      context.scaffoldMessenger.clearSnackBars();

      if (ref.read(castProvider).isCasting) {
        ref.read(castProvider.notifier).stop();
        context.scaffoldMessenger.showSnackBar(
          SnackBar(
            duration: const Duration(seconds: 2),
            content: Text(
              "local_asset_cast_failed".tr(),
              style: context.textTheme.bodyLarge?.copyWith(color: context.primaryColor),
            ),
          ),
        );
      }
    }
  }

  void _onEvent(Event event) {
    switch (event) {
      case TimelineReloadEvent():
        _onTimelineReloadEvent();
      case ViewerReloadAssetEvent():
        _onViewerReloadEvent();
      case ViewerExitAfterPlacesLocationEditEvent():
        _exitViewerAfterPlacesLocationEdit();
      case ViewerStackAssetDeletedEvent event:
        _onViewerStackAssetDeletedEvent(event);
      default:
    }
  }

  void _onViewerReloadEvent() {
    if (_totalAssets <= 1) {
      context.maybePop();
      return;
    }

    _dismissedHeroTag = ref.read(assetViewerProvider).currentAsset?.heroTag;

    final index = _pageController.page?.round() ?? _currentPage;
    final target = index >= _totalAssets - 1 ? index - 1 : index + 1;

    // Always advance the page index immediately so a pending timeline reload
    // cannot snap back to the dismissed asset while the buffer is still stale.
    _currentPage = target;

    unawaited(_prefetchAdjacentAsset(target));

    if (_pageController.hasClients) {
      _pageController.animateToPage(target, duration: Durations.medium1, curve: Curves.easeInOut);
    }
  }

  Future<void> _prefetchAdjacentAsset(int target) async {
    final timelineService = ref.read(timelineServiceProvider);
    final nextAsset = await timelineService.getAssetAsync(target);
    if (!mounted || _currentPage != target || nextAsset == null) {
      return;
    }

    final dismissedHeroTag = _dismissedHeroTag;
    if (dismissedHeroTag != null && nextAsset.heroTag == dismissedHeroTag) {
      return;
    }

    AssetViewer._setAsset(ref, nextAsset);
    _stackChildrenKeepAlive?.close();
    _stackChildrenKeepAlive = ref.read(stackChildrenNotifier(nextAsset).notifier).ref.keepAlive();
    _preloader.preload(target, context.sizeData);
    if (AirplayTimelinePlayback.isSupported && ref.read(airplayProvider)) {
      unawaited(
        AirplayTimelinePlayback.prefetchNeighbors(
          index: target,
          timelineService: timelineService,
          ref: ref,
        ),
      );
    }
    _handleCasting();
  }

  Future<void> _onViewerStackAssetDeletedEvent(ViewerStackAssetDeletedEvent event) async {
    final timelineAsset = ref.read(timelineServiceProvider).getAssetSafe(_currentPage);
    if (timelineAsset == null) {
      _onViewerReloadEvent();
      return;
    }

    final stackProvider = stackChildrenNotifier(timelineAsset);

    ref.invalidate(stackProvider);
    final stack = await ref.read(stackProvider.future);

    if (!mounted) {
      return;
    }

    if (stack.isEmpty) {
      _onViewerReloadEvent();
      return;
    }

    final targetIndex = math.min(event.stackIndex, stack.length - 1);
    ref.read(assetViewerProvider.notifier)
      ..setAsset(stack[targetIndex])
      ..setStackIndex(targetIndex);
  }

  void _onTimelineReloadEvent() {
    final timelineService = ref.read(timelineServiceProvider);
    final totalAssets = timelineService.totalAssets;

    if (totalAssets == 0) {
      if (_isPlacesScopedViewer) {
        _showMovedPlaceNotice();
        context.maybePop();
        return;
      }

      _fallbackAsset ??= ref.read(assetViewerProvider).currentAsset;
      if (_fallbackAsset != null) {
        _showMovedPlaceNotice();
      }
      if (_fallbackAsset == null) {
        context.maybePop();
      } else if (mounted) {
        setState(() {});
      }
      return;
    }

    final currentAsset = ref.read(assetViewerProvider).currentAsset;
    final dismissedHeroTag = _dismissedHeroTag;

    if (currentAsset?.heroTag == dismissedHeroTag) {
      if (_totalAssets != totalAssets && mounted) {
        setState(() => _totalAssets = totalAssets);
      }
      return;
    }

    final assetIndex = currentAsset != null ? timelineService.getIndex(currentAsset.heroTag) : null;
    final index = (assetIndex ?? _currentPage).clamp(0, totalAssets - 1);

    if (index != _currentPage) {
      _pageController.jumpToPage(index);
      unawaited(_onAssetChanged(index));
    } else if (currentAsset is RemoteAsset && currentAsset.stackId != null && assetIndex == null) {
      final timelineAsset = timelineService.getAssetSafe(index);
      if (timelineAsset is! RemoteAsset || currentAsset.stackId != timelineAsset.stackId) {
        unawaited(_onAssetChanged(index));
      }
    } else if (currentAsset != null && assetIndex == null) {
      unawaited(_onAssetChanged(index));
    }

    final displayedAsset = ref.read(assetViewerProvider).currentAsset;
    if (dismissedHeroTag != null && displayedAsset?.heroTag != dismissedHeroTag) {
      _dismissedHeroTag = null;
    }

    if (_totalAssets != totalAssets && mounted) {
      setState(() => _totalAssets = totalAssets);
    }
  }

  void _setSystemUIMode(bool controls, bool details) {
    final immersive = !controls || (CurrentPlatform.isIOS && details);
    unawaited(immersive ? SystemChrome.setEnabledSystemUIMode(SystemUiMode.immersiveSticky) : restoreEdgeToEdge());
  }

  @override
  Widget build(BuildContext context) {
    final showingControls = ref.watch(assetViewerProvider.select((s) => s.showingControls));
    final showingDetails = ref.watch(assetViewerProvider.select((s) => s.showingDetails));
    final isZoomed = ref.watch(assetViewerProvider.select((s) => s.isZoomed));
    final backgroundColor = showingDetails
        ? context.colorScheme.surface
        : Colors.black.withValues(alpha: ref.watch(assetViewerProvider.select((s) => s.backgroundOpacity)));

    ref.listen(castProvider.select((value) => value.isCasting), (_, isCasting) {
      if (!isCasting) {
        return;
      }
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _handleCasting();
      });
    });

    ref.listen(assetViewerProvider.select((value) => (value.showingControls, value.showingDetails)), (_, state) {
      final (controls, details) = state;
      _setSystemUIMode(controls, details);
    });

    return AnnotatedRegion(
      value: _viewerOverlayStyle,
      child: Scaffold(
        backgroundColor: backgroundColor,
        resizeToAvoidBottomInset: false,
        appBar: const ViewerTopAppBar(),
        extendBody: true,
        extendBodyBehindAppBar: true,
        floatingActionButton: IgnorePointer(
          ignoring: !showingControls,
          child: AnimatedOpacity(
            opacity: showingControls ? 1.0 : 0.0,
            duration: Durations.short2,
            child: const DownloadStatusFloatingButton(),
          ),
        ),
        bottomNavigationBar: const ViewerBottomAppBar(),
        body: Stack(
          children: [
            NotificationListener<ScrollEndNotification>(
              onNotification: _onScrollEnd,
              child: PhotoViewGestureDetectorScope(
                axis: Axis.horizontal,
                child: PageView.builder(
                  controller: _pageController,
                  physics: isZoomed
                      ? const NeverScrollableScrollPhysics()
                      : CurrentPlatform.isIOS
                      ? const FastScrollPhysics()
                      : const FastClampingScrollPhysics(),
                  itemCount: _itemCount,
                  itemBuilder: (context, index) => AssetPage(
                    index: _totalAssets > 0 ? index : 0,
                    heroOffset: _heroOffset,
                    fallbackAsset: _totalAssets == 0 ? _fallbackAsset : null,
                    onTapNavigate: _onTapNavigate,
                  ),
                ),
              ),
            ),
            if (!CurrentPlatform.isIOS)
              IgnorePointer(
                child: AnimatedContainer(
                  duration: Durations.short2,
                  color: Colors.black.withValues(alpha: showingDetails ? 0.6 : 0.0),
                  height: context.padding.top,
                ),
              ),
          ],
        ),
      ),
    );
  }
}
