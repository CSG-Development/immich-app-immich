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
    title: 'Manage your photo library',
    description: 'You can copy, move, delete',
  ),
  OnboardingSlide(
    image: 'assets/onboarding-1.png',
    title: 'Share moments securely',
    description: 'You can share privately or publicly',
  ),
  OnboardingSlide(
    image: 'assets/onboarding-1.png',
    title: 'Keep your media in sync',
    description:
        'Upload from your phone, access from your desktop. Personal Cloud Photos keeps everything connected.',
  ),
  OnboardingSlide(
    image: 'assets/onboarding-1.png',
    title: 'Relive the highlights',
    description: 'Let Personal Cloud Photos bring your memories back to life',
  ),
];


