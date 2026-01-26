import 'package:flutter/material.dart';

class MultiFingerTapDetector extends StatefulWidget {
  final VoidCallback onFiveTwoFingerTaps;
  final Widget child;

  const MultiFingerTapDetector({super.key, required this.onFiveTwoFingerTaps, required this.child});

  @override
  MultiFingerTapDetectorState createState() => MultiFingerTapDetectorState();
}

class MultiFingerTapDetectorState extends State<MultiFingerTapDetector> {
  final List<PointerEvent> _activePointers = [];
  final List<DateTime> _tapTimes = [];
  final int _requiredFingers = 2;
  final int _requiredTaps = 5;
  final Duration _timeWindow = const Duration(seconds: 2);

  void _handlePointerDown(PointerDownEvent event) {
    _activePointers.add(event);

    if (_activePointers.length == _requiredFingers) {
      _tapTimes.add(DateTime.now());

      _tapTimes.removeWhere((time) => DateTime.now().difference(time) > _timeWindow);

      if (_tapTimes.length >= _requiredTaps) {
        widget.onFiveTwoFingerTaps();
        _tapTimes.clear();
      }
    }
  }

  void _handlePointerUp(PointerUpEvent event) {
    _activePointers.removeWhere((e) => e.pointer == event.pointer);
  }

  void _handlePointerCancel(PointerCancelEvent event) {
    _activePointers.removeWhere((e) => e.pointer == event.pointer);
  }

  @override
  Widget build(BuildContext context) {
    return Listener(
      onPointerDown: _handlePointerDown,
      onPointerUp: _handlePointerUp,
      onPointerCancel: _handlePointerCancel,
      child: widget.child,
    );
  }
}
