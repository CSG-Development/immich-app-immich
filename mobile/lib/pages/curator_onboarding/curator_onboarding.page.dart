import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:flutter/services.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/constants/onboarding.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
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

    _scrollControllers.addAll(List.generate(_onboardingSteps.length, (index) => ScrollController()));

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
      _pageController.nextPage(duration: const Duration(milliseconds: 300), curve: Curves.easeInOut);
    } else {
      _finishOnboarding();
    }
  }

  void _skip() => _finishOnboarding();

  Future<void> handleSyncFlow() async {
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
      handleSyncFlow();
      ref.read(websocketProvider.notifier).connect();
      context.replaceRoute(const TabShellRoute());
      return;
    }
    context.replaceRoute(const TabControllerRoute());
  }

  Widget _buildScrollableStep(OnboardingSlide step, bool isTablet, bool isLandscape, int index) {
    final imageWidth = isLandscape && !isTablet ? 120.0 : 312.0;
    final scrollController = _scrollControllers[index];

    Widget content = Column(
      mainAxisAlignment: isTablet ? MainAxisAlignment.center : MainAxisAlignment.start,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Center(child: Image.asset(step.image, width: imageWidth)),
        const SizedBox(height: 40),
        Text(
          step.title.tr(),
          textAlign: TextAlign.left,
          style: const TextStyle(fontSize: 34.0, fontWeight: FontWeight.bold),
        ),
        const SizedBox(height: 24),
        Text(step.description.tr(), textAlign: TextAlign.left, style: const TextStyle(fontSize: 16.0)),
      ],
    );

    final scrollView = SingleChildScrollView(
      controller: scrollController,
      child: Padding(
        padding: const EdgeInsets.only(bottom: 68.0),
        child: Center(
          child: ConstrainedBox(
            constraints: BoxConstraints(maxWidth: isLandscape || isTablet ? 312.0 : double.infinity),
            child: Padding(padding: const EdgeInsets.all(24.0), child: content),
          ),
        ),
      ),
    );

    return isTablet ? Center(child: scrollView) : scrollView;
  }

  @override
  Widget build(BuildContext context) {
    final media = MediaQuery.of(context);
    final isLandscape = media.orientation == Orientation.landscape;
    final isTablet = context.isTablet;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: context.isDarkTheme ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: SafeArea(
          child: Stack(
            children: [
              Column(
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
                          if (isLandscape && _scrollControllers[index].hasClients) {
                            _scrollControllers[index].jumpTo(0);
                          }
                        });
                      },
                      itemBuilder: (context, index) {
                        final step = _onboardingSteps[index];
                        return _buildScrollableStep(step, isTablet, isLandscape, index);
                      },
                    ),
                  ),
                ],
              ),
              Positioned(
                bottom: 0,
                left: 0,
                right: 0,
                child: Container(
                  height: 68.0,
                  decoration: BoxDecoration(
                    gradient: LinearGradient(
                      begin: Alignment.topCenter,
                      end: Alignment.bottomCenter,
                      colors: [context.colorScheme.surface.withValues(alpha: 0.0), context.colorScheme.surface],
                      stops: const [0.0, 0.25],
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 60,
                        child: _currentPage < _onboardingSteps.length - 1
                            ? TextButton(
                                onPressed: _skip,
                                child: Text(
                                  "curator.onboarding.skip".tr(),
                                  style: TextStyle(color: context.colorScheme.onSurface, fontWeight: FontWeight.w500),
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
                                  ? context.colorScheme.onSurface
                                  : context.colorScheme.onSurface.withAlpha(50),
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
                                  colorFilter: ColorFilter.mode(context.colorScheme.onSurface, BlendMode.srcIn),
                                )
                              : Text(
                                  "curator.onboarding.done".tr(),
                                  style: TextStyle(color: context.colorScheme.onSurface, fontWeight: FontWeight.w500),
                                ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
