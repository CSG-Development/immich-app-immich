import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';

class LoadingIcon extends StatefulWidget {
  final String? text;
  const LoadingIcon({super.key, this.text});

  @override
  State<LoadingIcon> createState() => _LoadingIconState();
}

class _LoadingIconState extends State<LoadingIcon>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 2),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 16.0),
      child: Column(
        children: [
          FittedBox(
            child: RotationTransition(
              turns: _controller,
              child: SvgPicture.asset(
                'assets/circular-progress-indicator.svg',
                height: 48,
              ),
            ),
          ),
          ...widget.text != null
              ? [
                  const SizedBox(height: 16.0),
                  Text(
                    widget.text!,
                    style: const TextStyle(),
                  ),
                ]
              : [],
        ],
      ),
    );
  }
}
