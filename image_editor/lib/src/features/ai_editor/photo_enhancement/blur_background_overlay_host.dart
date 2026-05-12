import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/ai_overlay_host.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/blur_background_manual_overlay.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

/// Overlay host for the blur background feature.
///
/// Wraps the image with the manual mask editor overlay, allowing the user
/// to paint a custom mask for background blur.
class BlurBackgroundOverlayHost extends StatefulWidget {
  const BlurBackgroundOverlayHost({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.backgroundRemovalService,
    required this.onDone,
    required this.onCancel,
  });

  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final BackgroundRemovalService backgroundRemovalService;
  final Future<void> Function(Uint8List mask) onDone;
  final VoidCallback onCancel;

  /// Shows the blur background overlay in a full-screen dialog.
  static Future<void> show({
    required BuildContext context,
    required ThemeData theme,
    required Uint8List imageBytes,
    required int imageWidth,
    required int imageHeight,
    required BackgroundRemovalService backgroundRemovalService,
    required Future<void> Function(Uint8List mask) onDone,
    required VoidCallback onCancel,
  }) {
    return showDialog<void>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => Theme(
        data: theme,
        child: BlurBackgroundOverlayHost(
          imageBytes: imageBytes,
          imageWidth: imageWidth,
          imageHeight: imageHeight,
          backgroundRemovalService: backgroundRemovalService,
          onDone: onDone,
          onCancel: onCancel,
        ),
      ),
    );
  }

  @override
  State<BlurBackgroundOverlayHost> createState() =>
      _BlurBackgroundOverlayHostState();
}

class _BlurBackgroundOverlayHostState
    extends State<BlurBackgroundOverlayHost> {
  Future<void> _closeWithDone(Uint8List mask) async {
    await widget.onDone(mask);
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  void _closeWithCancel() {
    widget.onCancel();
    if (!mounted) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return AiOverlayHost(
      editorImage: EditorImage(byteArray: widget.imageBytes),
      builder: (bytes, width, height) {
        return BlurBackgroundManualOverlay(
          imageBytes: bytes,
          imageSize: Size(width.toDouble(), height.toDouble()),
          backgroundRemovalService: widget.backgroundRemovalService,
          onDone: (mask) async {
            if (mask != null) {
              await _closeWithDone(mask);
            } else {
              _closeWithCancel();
            }
          },
          onCancel: _closeWithCancel,
        );
      },
    );
  }
}