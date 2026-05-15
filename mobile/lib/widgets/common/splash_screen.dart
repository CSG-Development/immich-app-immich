import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/widgets/forms/login/login_brand_strings.dart';

const Color _splashBrandGreen = Color(0xFF3DB801);
const Color _splashBrandTeal = Color(0xFF02B2AB);

const LinearGradient _splashGradient = LinearGradient(
  begin: Alignment(-0.96, -0.96),
  end: Alignment(1.0, -0.28),
  colors: [_splashBrandGreen, _splashBrandTeal],
);

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isTablet = context.isTablet;
    final isLandscape = context.orientation == Orientation.landscape;
    final isPhoneLandscape = !isTablet && isLandscape;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _splashOverlayStyle(context),
      child: PopScope(
        canPop: false,
        child: Scaffold(
          extendBody: true,
          backgroundColor: Colors.transparent,
          body: Stack(
            children: [
              const SizedBox.expand(
                child: DecoratedBox(decoration: BoxDecoration(gradient: _splashGradient)),
              ),
              SafeArea(
                child: Center(child: _SplashBrandedColumn(isPhoneLandscape: isPhoneLandscape)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SplashBrandedColumn extends StatelessWidget {
  const _SplashBrandedColumn({this.isPhoneLandscape = false});

  final bool isPhoneLandscape;

  @override
  Widget build(BuildContext context) {
    final double logoWidth = isPhoneLandscape ? 94 : 182;
    final double aboveLogoSpacing = isPhoneLandscape ? 24 : 80;
    final double belowLogoSpacing = isPhoneLandscape ? 10 : 16;

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        SvgPicture.asset(
          LoginBrandStrings.wordmarkSvg,
          width: 162,
          fit: BoxFit.contain,
          colorFilter: const ColorFilter.mode(Colors.white, BlendMode.srcIn),
        ),
        SizedBox(height: aboveLogoSpacing),
        SvgPicture.asset(
          LoginBrandStrings.splashLogoWhiteSvg,
          width: logoWidth,
          fit: BoxFit.contain,
        ),
        SizedBox(height: belowLogoSpacing),
        SvgPicture.asset(
          LoginBrandStrings.splashPhotosTextSvg,
          height: 40,
          fit: BoxFit.contain,
        ),
      ],
    );
  }
}

SystemUiOverlayStyle _splashOverlayStyle(BuildContext context) {
  return const SystemUiOverlayStyle(
    systemNavigationBarColor: Colors.transparent,
    systemNavigationBarIconBrightness: Brightness.light,
  );
}
