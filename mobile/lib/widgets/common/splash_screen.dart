import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final isAndroid = Platform.isAndroid;
    final backgroundColor = isAndroid ? const Color(0xFF19181E) : Theme.of(context).colorScheme.surface;

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: _splashOverlayStyle(context),
      child: PopScope(
        canPop: false,
        child: Scaffold(
          backgroundColor: backgroundColor,
          body: const SizedBox.expand(
            child: Image(
              image: AssetImage('assets/immich-splash.png'),
              filterQuality: FilterQuality.medium,
              fit: BoxFit.fitHeight,
            ),
          ),
        ),
      ),
    );
  }
}

SystemUiOverlayStyle _splashOverlayStyle(BuildContext context) {
  // Splash is dark; prefer light icons. Keep gesture nav edge-to-edge.
  Color navColor = Colors.transparent;
  Brightness iconBrightness = Brightness.light;

  if (Platform.isAndroid) {
    // Force dark nav bar on splash for all Android modes
    navColor = const Color(0xFF000000);
  }

  return SystemUiOverlayStyle(systemNavigationBarColor: navColor, systemNavigationBarIconBrightness: iconBrightness);
}
