import 'dart:math' as math;

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/pages/security/lock_flow.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/services/secure_storage.service.dart';
import 'package:immich_mobile/utils/hooks/add_biometric_auth_hook.dart';
import 'package:immich_mobile/utils/hooks/app_settings_update_hook.dart';

enum _PatternStage { verifyExisting, createNew, confirmNew }

@RoutePage()
class PatternLockPage extends HookConsumerWidget {
  const PatternLockPage({super.key, this.flow = LockFlow.validate, this.onSuccess});

  final LockFlow flow;
  final VoidCallback? onSuccess;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secureStorage = ref.watch(secureStorageServiceProvider);

    String t(String key, String fallback) {
      final value = key.tr();
      return value == key ? fallback : value;
    }

    final stage = useState<_PatternStage>(
      flow == LockFlow.create ? _PatternStage.createNew : _PatternStage.verifyExisting,
    );
    final firstEntry = useState<String?>(null);
    final hasError = useState<bool>(false);
    final errorText = useState<String?>(null);
    final isLoading = useState<bool>(false);

    String _encode(List<int> nodes) => nodes.join('-');

    final enableBiometric = useAppSettingsState(AppSettingsEnum.enableBiometric);
    final handleAddBiometric = useAddBiometricAuthHook(context, ref);

    String getTitle() {
      switch (stage.value) {
        case _PatternStage.verifyExisting:
          return flow == LockFlow.remove ? 'curator.pattern_remove_title'.tr() : 'curator.pattern_enter_title'.tr();
        case _PatternStage.createNew:
          return 'curator.pattern_create_title'.tr();
        case _PatternStage.confirmNew:
          return 'curator.pattern_confirm_title'.tr();
      }
    }

    String getSubtitle() {
      switch (stage.value) {
        case _PatternStage.verifyExisting:
          return 'curator.pattern_enter_subtitle'.tr();
        case _PatternStage.createNew:
          return 'curator.pattern_create_subtitle'.tr();
        case _PatternStage.confirmNew:
          return 'curator.pattern_confirm_subtitle'.tr();
      }
    }

    String getError() {
      switch (stage.value) {
        case _PatternStage.verifyExisting:
          return 'curator.pattern_enter_error'.tr();
        case _PatternStage.createNew:
          return 'curator.pattern_create_error'.tr();
        case _PatternStage.confirmNew:
          return 'curator.pattern_confirm_error'.tr();
      }
    }

    Future<void> handleCompleted(List<int> nodes) async {
      if (isLoading.value) return;
      if (nodes.length < 3) {
        hasError.value = true;
        errorText.value = t('pattern_error_short', 'Pattern is too short');
        return;
      }

      final encoded = _encode(nodes);

      switch (stage.value) {
        case _PatternStage.verifyExisting:
          isLoading.value = true;
          try {
            final saved = await secureStorage.read(kSecuredPattern);
            if (saved == null) {
              hasError.value = true;
              errorText.value = t('pattern_error_missing', 'No pattern saved');
              return;
            }

            if (saved != encoded) {
              hasError.value = true;
              errorText.value = t('pattern_error_incorrect', 'Incorrect pattern');
              return;
            }

            if (flow == LockFlow.remove) {
              await secureStorage.delete(kSecuredPattern);
            }

            // ignore: use_build_context_synchronously
            context.maybePop(true);
            onSuccess?.call();
          } finally {
            isLoading.value = false;
          }
          break;
        case _PatternStage.createNew:
          firstEntry.value = encoded;
          hasError.value = false;
          errorText.value = null;
          stage.value = _PatternStage.confirmNew;
          break;
        case _PatternStage.confirmNew:
          if (firstEntry.value == encoded) {
            isLoading.value = true;
            try {
              await secureStorage.write(kSecuredPattern, encoded);

              if (!enableBiometric.value) {
                final shouldEnableBiometric = await handleAddBiometric();
                if (shouldEnableBiometric) {
                  enableBiometric.value = shouldEnableBiometric;
                }
              }

              // ignore: use_build_context_synchronously
              context.maybePop(true);
            } finally {
              isLoading.value = false;
            }
          } else {
            hasError.value = true;
            errorText.value = t('pattern_error_mismatch', 'Patterns do not match');
          }
          break;
      }
    }

    void onStartDrawing() {
      hasError.value = false;
      errorText.value = null;
    }

    handleLogout() {
      ref.read(authProvider.notifier).logout();
      context.replaceRoute(const LoginRoute());
    }

    return PopScope(
      canPop: flow != LockFlow.validate,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && result == true) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          title: Text('curator.pattern_title'.tr()),
          automaticallyImplyLeading: flow != LockFlow.validate,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 24),
                      child: Text(
                        getTitle(),
                        style: context.textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const SizedBox(height: 12),
                    if (getSubtitle().isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 40),
                        child: Text(
                          getSubtitle(),
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (hasError.value && errorText.value != null) ...[
                      Text(
                        errorText.value!,
                        style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.error, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    Center(
                      child: _PatternBoard(
                        hasError: hasError.value,
                        isDisabled: isLoading.value,
                        onStart: onStartDrawing,
                        onCompleted: handleCompleted,
                      ),
                    ),
                  ],
                ),
              ),
              if (flow == LockFlow.validate && hasError.value)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 8.0),
                  child: GestureDetector(
                    onTap: handleLogout,
                    child: Text(
                      "log_out".tr(),
                      style: TextStyle(
                        color: context.themeData.primaryColor,
                        fontSize: 16,
                        fontWeight: FontWeight.w500,
                      ),
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

class _PatternBoard extends StatefulWidget {
  const _PatternBoard({
    required this.hasError,
    required this.isDisabled,
    required this.onCompleted,
    required this.onStart,
  });

  final bool hasError;
  final bool isDisabled;
  final void Function(List<int> nodes) onCompleted;
  final VoidCallback onStart;

  @override
  State<_PatternBoard> createState() => _PatternBoardState();
}

class _PatternBoardState extends State<_PatternBoard> {
  static const int _gridSize = 3;
  static const double _nodeRadius = 15 / 2;

  final List<int> _activeNodes = <int>[];
  Offset? _currentPosition;
  late List<Offset> _centers;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _centers = List<Offset>.generate(_gridSize * _gridSize, (index) => Offset.zero);
  }

  void _reset() {
    _activeNodes.clear();
    _currentPosition = null;
  }

  void _handlePanStart(Offset position) {
    widget.onStart();
    _reset();
    _updateActiveNode(position);
  }

  void _handlePanUpdate(Offset position) {
    _currentPosition = position;
    _updateActiveNode(position);
    setState(() {});
  }

  void _handlePanEnd() {
    if (_activeNodes.isNotEmpty) {
      widget.onCompleted(List<int>.from(_activeNodes));
    }
    setState(_reset);
  }

  void _updateActiveNode(Offset position) {
    final hit = _hitTest(position);
    if (hit != null && !_activeNodes.contains(hit)) {
      setState(() {
        _activeNodes.add(hit);
      });
    }
  }

  int? _hitTest(Offset position) {
    for (var i = 0; i < _centers.length; i++) {
      if ((position - _centers[i]).distance <= _nodeRadius * 1.5) {
        return i;
      }
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final color = widget.hasError ? context.colorScheme.error : context.colorScheme.primary;
    final inactiveColor = context.colorScheme.onSurface.withAlpha(222);

    return LayoutBuilder(
      builder: (context, constraints) {
        final size = math.min(constraints.maxWidth, constraints.maxHeight);
        final boardSize = math.min(size, 360.0);
        final spacing = boardSize / (_gridSize + 1);
        _centers = List<Offset>.generate(_gridSize * _gridSize, (index) {
          final row = index ~/ _gridSize;
          final col = index % _gridSize;
          return Offset(spacing * (col + 1), spacing * (row + 1));
        });

        return AbsorbPointer(
          absorbing: widget.isDisabled,
          child: GestureDetector(
            onPanStart: (details) => _handlePanStart(details.localPosition),
            onPanUpdate: (details) => _handlePanUpdate(details.localPosition),
            onPanEnd: (_) => _handlePanEnd(),
            child: SizedBox(
              width: boardSize,
              height: boardSize,
              child: CustomPaint(
                painter: _PatternPainter(
                  centers: _centers,
                  activeNodes: _activeNodes,
                  fingerPosition: _currentPosition,
                  // activeColor: color,
                  activeColor: inactiveColor,
                  inactiveColor: inactiveColor,
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _PatternPainter extends CustomPainter {
  _PatternPainter({
    required this.centers,
    required this.activeNodes,
    required this.fingerPosition,
    required this.activeColor,
    required this.inactiveColor,
  });

  final List<Offset> centers;
  final List<int> activeNodes;
  final Offset? fingerPosition;
  final Color activeColor;
  final Color inactiveColor;

  static const double _nodeRadius = 15 / 2;

  @override
  void paint(Canvas canvas, Size size) {
    final nodePaint = Paint()
      ..color = inactiveColor
      ..style = PaintingStyle.fill;

    final activeNodePaint = Paint()
      ..color = activeColor
      ..style = PaintingStyle.fill;

    final linePaint = Paint()
      ..color = activeColor
      ..strokeWidth = 2
      ..strokeCap = StrokeCap.round;

    // Draw lines between active nodes.
    for (var i = 0; i < activeNodes.length - 1; i++) {
      final start = centers[activeNodes[i]];
      final end = centers[activeNodes[i + 1]];
      canvas.drawLine(start, end, linePaint);
    }

    // Draw the trailing line to the finger position.
    if (activeNodes.isNotEmpty && fingerPosition != null) {
      final last = centers[activeNodes.last];
      canvas.drawLine(last, fingerPosition!, linePaint..color = activeColor.withOpacity(0.6));
    }

    // Draw nodes.
    for (var i = 0; i < centers.length; i++) {
      final isActive = activeNodes.contains(i);
      canvas.drawCircle(centers[i], _nodeRadius, isActive ? activeNodePaint : nodePaint);
    }
  }

  @override
  bool shouldRepaint(covariant _PatternPainter oldDelegate) {
    return oldDelegate.activeNodes != activeNodes ||
        oldDelegate.fingerPosition != fingerPosition ||
        oldDelegate.activeColor != activeColor ||
        oldDelegate.inactiveColor != inactiveColor;
  }
}
