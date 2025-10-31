import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/constants/onboarding.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';

final _onboardingSteps = kCuratorOnboardingSlidesData;

@RoutePage()
class CuratorOnboardingPage extends ConsumerStatefulWidget {
  const CuratorOnboardingPage({super.key});

  @override
  ConsumerState<CuratorOnboardingPage> createState() => _CuratorOnboardingPageState();
}

class _CuratorOnboardingPageState extends ConsumerState<CuratorOnboardingPage> {
  final PageController _pageController = PageController();
  final List<ScrollController> _scrollControllers = [];
  int _currentPage = 0;

  @override
  void initState() {
    super.initState();

    _scrollControllers.addAll(
      List.generate(
        _onboardingSteps.length,
        (index) => ScrollController(),
      ),
    );

    final viewedCount = Store.tryGet<int>(StoreKey.onboardingViewedCount) ?? 0;
    final startIndex = viewedCount.clamp(0, _onboardingSteps.length - 1);

    final ensuredViewedCount = startIndex + 1;
    if (viewedCount < ensuredViewedCount) {
      Store.put(StoreKey.onboardingViewedCount, ensuredViewedCount);
    }

    if (startIndex > 0) {
      _currentPage = startIndex;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) {
          _pageController.jumpToPage(startIndex);
        }
      });
    }
  }

  @override
  void dispose() {
    for (var controller in _scrollControllers) {
      controller.dispose();
    }
    _pageController.dispose();
    super.dispose();
  }

  void _nextPage() {
    if (_currentPage < _onboardingSteps.length - 1) {
      _pageController.nextPage(
        duration: const Duration(milliseconds: 300),
        curve: Curves.easeInOut,
      );
    } else {
      _finishOnboarding();
    }
  }

  void _skip() => _finishOnboarding();

  Future<void> _handleSyncFlow() async {
    final backgroundManager = ref.read(backgroundSyncProvider);

    await backgroundManager.syncLocal(full: true);
    await backgroundManager.syncRemote();
    await backgroundManager.hashAssets();

    if (Store.get(StoreKey.syncAlbums, false)) {
      await backgroundManager.syncLinkedAlbum();
    }
  }

  void _finishOnboarding() async {
    await Store.put(StoreKey.onboardingWasShown, true);
    await Store.delete(StoreKey.onboardingViewedCount);
    final isBeta = Store.isBetaTimelineEnabled;
    if (isBeta) {
      await ref.read(galleryPermissionNotifier.notifier).requestGalleryPermission();
      await _handleSyncFlow();
      ref.read(websocketProvider.notifier).connect();
      context.replaceRoute(const TabShellRoute());
      return;
    }
    context.replaceRoute(const TabControllerRoute());
  }

  Widget _buildFixedStep(OnboardingSlide step, bool isTablet) {
    final imageHeight = isTablet ? 312.0 : 250.0;

    Widget content = Column(
      mainAxisAlignment:
          isTablet ? MainAxisAlignment.center : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child:
              Image.asset(step.image, height: imageHeight, width: imageHeight),
        ),
        const SizedBox(height: 40),
        Text(
          step.title,
          textAlign: TextAlign.left,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.w700,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          step.description,
          textAlign: TextAlign.left,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white,
          ),
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsets.all(24.0),
      child: isTablet
          ? Center(child: SizedBox(width: 312, child: content))
          : content,
    );
  }

  Widget _buildScrollableStep(OnboardingSlide step, bool isTablet, int index) {
    final imageHeight = isTablet ? 312.0 : 120.0;
    final scrollController = _scrollControllers[index];

    Widget content = Column(
      mainAxisAlignment:
          isTablet ? MainAxisAlignment.center : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(
          child:
              Image.asset(step.image, height: imageHeight, width: imageHeight),
        ),
        const SizedBox(height: 40),
        Text(
          step.title,
          textAlign: TextAlign.left,
          style: const TextStyle(
            fontSize: 24,
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          step.description,
          textAlign: TextAlign.left,
          style: const TextStyle(fontSize: 16, color: Colors.white),
        ),
      ],
    );

    if (isTablet) {
      return Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 312),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: content,
          ),
        ),
      );
    }

    return SingleChildScrollView(
      controller: scrollController,
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 312),
          child: Padding(
            padding: const EdgeInsets.all(24.0),
            child: content,
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final isTablet = media.size.shortestSide >= 600;

    return Scaffold(
      body: Stack(
        children: [
          Positioned.fill(
            child: Image.asset(
              'assets/background.png',
              fit: BoxFit.cover,
            ),
          ),
          SafeArea(
            child: Column(
              children: [
                Expanded(
                  child: PageView.builder(
                    controller: _pageController,
                    itemCount: _onboardingSteps.length,
                    onPageChanged: (index) {
                      setState(() => _currentPage = index);
                      final prev = Store.tryGet<int>(StoreKey.onboardingViewedCount) ?? 0;
                      final next = index + 1;
                      if (next > prev) {
                        Store.put(StoreKey.onboardingViewedCount, next);
                      }
                      WidgetsBinding.instance.addPostFrameCallback((_) {
                        if (isLandscape &&
                            !isTablet &&
                            _scrollControllers[index].hasClients) {
                          _scrollControllers[index].jumpTo(0);
                        }
                      });
                    },
                    itemBuilder: (context, index) {
                      final step = _onboardingSteps[index];
                      return isLandscape
                          ? _buildScrollableStep(step, isTablet, index)
                          : _buildFixedStep(step, isTablet);
                    },
                  ),
                ),
                SizedBox(
                  height: 68.0,
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 60,
                        child: _currentPage < _onboardingSteps.length - 1
                            ? TextButton(
                                onPressed: _skip,
                                child: const Text(
                                  "Skip",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                              )
                            : const SizedBox(),
                      ),
                      const SizedBox(width: 42),
                      Row(
                        children: List.generate(
                          _onboardingSteps.length,
                          (index) => Container(
                            margin: const EdgeInsets.symmetric(horizontal: 4),
                            width: 8,
                            height: 8,
                            decoration: BoxDecoration(
                              shape: BoxShape.circle,
                              color: _currentPage == index
                                  ? Colors.white
                                  : Colors.white54,
                            ),
                          ),
                        ),
                      ),
                      const SizedBox(width: 42),
                      SizedBox(
                        width: 60,
                        child: GestureDetector(
                          onTap: _nextPage,
                          child: _currentPage < _onboardingSteps.length - 1
                              ? SvgPicture.asset(
                                  'assets/arrow-forward.svg',
                                )
                              : const Text(
                                  "Done",
                                  style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 14,
                                  ),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
