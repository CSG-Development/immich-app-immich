class OnboardingSlide {
  final String image;
  final String title;
  final String description;

  const OnboardingSlide({
    required this.image,
    required this.title,
    required this.description,
  });
}

const List<OnboardingSlide> kCuratorOnboardingSlidesData = [
  OnboardingSlide(
    image: 'assets/onboarding-1.png',
    title: "curator.onboarding.slide1.title",
    description: "curator.onboarding.slide1.description",
  ),
  OnboardingSlide(
    image: 'assets/onboarding-2.png',
    title: "curator.onboarding.slide2.title",
    description: "curator.onboarding.slide2.description",
  ),
  OnboardingSlide(
    image: 'assets/onboarding-3.png',
    title: "curator.onboarding.slide3.title",
    description:
"curator.onboarding.slide3.description",
  ),
  OnboardingSlide(
    image: 'assets/onboarding-4.png',
    title: "curator.onboarding.slide4.title",
    description: "curator.onboarding.slide4.description",
  ),
];


