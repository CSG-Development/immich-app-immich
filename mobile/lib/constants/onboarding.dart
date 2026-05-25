class OnboardingSlide {
  final String image;
  final String imageType;
  final String title;
  final String description;

  const OnboardingSlide({
    required this.image,
    required this.title,
    required this.description,
    this.imageType = 'png',
  });
}

const List<OnboardingSlide> kCuratorOnboardingSlidesData = [
  OnboardingSlide(
    image: 'assets/splash/login_logo_mark.svg',
    imageType: 'svg',
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


