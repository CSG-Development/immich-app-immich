import 'package:flutter/material.dart';

class LockResponsiveLayout extends StatelessWidget {
  const LockResponsiveLayout({
    super.key,
    required this.isLandscapePhone,
    required this.left,
    required this.right,
  });

  final bool isLandscapePhone;
  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    if (isLandscapePhone) {
      return Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 24),
              child: left,
            ),
          ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 24),
              child: right,
            ),
          ),
        ],
      );
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        left,
        const SizedBox(height: 32),
        right,
      ],
    );
  }
}

