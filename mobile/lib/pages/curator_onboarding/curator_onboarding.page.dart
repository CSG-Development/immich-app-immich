import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:immich_mobile/routing/router.dart';

class OnboardingStep {
  final String image;
  final String title;
  final String description;

  OnboardingStep({
    required this.image,
    required this.title,
    required this.description,
  });
}

final _onboardingSteps = [
  OnboardingStep(
    image: 'assets/onboarding-1.png',
    title: 'Manage your photo library',
    description: 'You can copy, move, delete',
  ),
  OnboardingStep(
    image: 'assets/onboarding-1.png',
    title: 'Share moments securely',
    description: 'You can share privately or publicly',
  ),
  OnboardingStep(
    image: 'assets/onboarding-1.png',
    title: 'Keep your media in sync',
    description:
        'Upload from your phone, access from your desktop. Immich keeps everything connected.',
  ),
  OnboardingStep(
    image: 'assets/onboarding-1.png',
    title: 'Relive the highlights',
    description: 'Let Immich bring your memories back to life',
  ),
];

@RoutePage()
class CuratorOnboardingPage extends StatefulWidget {
  const CuratorOnboardingPage({super.key});

  @override
  State<CuratorOnboardingPage> createState() => _CuratorOnboardingPageState();
}

class _CuratorOnboardingPageState extends State<CuratorOnboardingPage> {
  final PageController _pageController = PageController();
  int _currentPage = 0;

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

  void _finishOnboarding() {
    context.replaceRoute(const TabControllerRoute());
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
                    onPageChanged: (index) =>
                        setState(() => _currentPage = index),
                    itemBuilder: (context, index) {
                      final step = _onboardingSteps[index];
                      return isLandscape
                          ? _buildScrollableStep(step, isTablet)
                          : _buildFixedStep(step, isTablet);
                    },
                  ),
                ),
                Padding(
                  padding: const EdgeInsets.all(22),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      SizedBox(
                        width: 60,
                        child: TextButton(
                          onPressed: _skip,
                          child: const Text(
                            "Skip",
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: 14,
                            ),
                          ),
                        ),
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
                          child: SvgPicture.asset(
                            'assets/arrow-forward.svg',
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

  Widget _buildFixedStep(OnboardingStep step, bool isTablet) {
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
            fontWeight: FontWeight.bold,
            color: Colors.white,
          ),
        ),
        const SizedBox(height: 12),
        Text(
          step.description,
          textAlign: TextAlign.left,
          style: const TextStyle(
            fontSize: 16,
            color: Colors.white70,
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

  Widget _buildScrollableStep(OnboardingStep step, bool isTablet) {
    final imageHeight = isTablet ? 312.0 : 120.0;

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
          style: const TextStyle(fontSize: 16, color: Colors.white70),
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
}
