import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/animal_insertion/animal_insertion_overlay.dart';
import 'package:image_editor/src/features/ai_editor/ai_editor_actions.dart';
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/model_download_dialog.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

/// Simple model object passed between steps of the animal insertion flow.
class AnimalInsertionParams {
  AnimalInsertionParams({
    required this.editorImage,
    required this.actions,
    required this.backgroundRemovalService,
    required this.backgroundEffectMode,
  });

  final EditorImage editorImage;
  final AiEditorActions actions;
  final BackgroundRemovalService backgroundRemovalService;
  final BackgroundEffectMode backgroundEffectMode;
}

/// Entry point widget to drive the animal insertion flow:
/// 1) Let host app pick an animal image and provide its bytes.
/// 2) Run background removal on the animal image.
/// 3) Let the user draw a placement mask on the base image.
/// 4) Compose the images and return the result via [onCompleted].
class AnimalInsertionFlow extends StatefulWidget {
  const AnimalInsertionFlow({
    super.key,
    required this.params,
    required this.onCompleted,
    required this.onCancel,
    required this.animalImageBytes,
  });

  final AnimalInsertionParams params;
  final void Function(Uint8List resultBytes) onCompleted;
  final VoidCallback onCancel;

  /// Raw bytes of the animal image chosen by the user.
  final Uint8List animalImageBytes;

  @override
  State<AnimalInsertionFlow> createState() => _AnimalInsertionFlowState();
}

class _AnimalInsertionFlowState extends State<AnimalInsertionFlow> {
  bool _isProcessing = true;
  Uint8List? _animalCutoutBytes;
  String? _error;

  @override
  void initState() {
    super.initState();
    _prepareAnimalCutout();
  }

  Future<void> _prepareAnimalCutout() async {
    setState(() {
      _isProcessing = true;
      _error = null;
    });

    try {
      // Ensure model is available for background removal of the animal image.
      final ok = await showModelDownloadDialog(
        context,
        modelPathOrUrl: widget.params.backgroundRemovalService.modelPathOrUrl,
        modelName: 'Animal cutout',
      );
      if (!ok || !mounted) {
        setState(() {
          _isProcessing = false;
          _error = 'Model not available.';
        });
        return;
      }

      final cutout = await widget.params.backgroundRemovalService.removeBackground(
        widget.animalImageBytes,
        mode: widget.params.backgroundEffectMode,
      );

      if (!mounted) return;
      setState(() {
        _animalCutoutBytes = cutout;
        _isProcessing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = 'Failed to prepare animal image.';
        _isProcessing = false;
      });
    }
  }

  Future<void> _handlePlacementApplied(AnimalInsertionResult result) async {
    final baseBytes = await widget.params.editorImage.safeByteArray();
    if (!mounted) return;

    final composed = await widget.params.actions.insertAnimal(
      baseImageBytes: baseBytes,
      animalCutoutBytes: result.animalCutoutBytes,
      placementMask: result.placementMask,
    );
    if (!mounted) return;
    widget.onCompleted(composed);
  }

  @override
  Widget build(BuildContext context) {
    if (_isProcessing) {
      return const Scaffold(
        backgroundColor: Colors.black87,
        body: Center(
          child: CircularProgressIndicator(),
        ),
      );
    }

    if (_error != null || _animalCutoutBytes == null) {
      return Scaffold(
        backgroundColor: Colors.black87,
        appBar: AppBar(
          title: const Text('Animal insertion'),
          backgroundColor: Colors.black,
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Text(
              _error ?? 'Failed to prepare animal image.',
              style: const TextStyle(color: Colors.white70),
              textAlign: TextAlign.center,
            ),
          ),
        ),
      );
    }

    return FutureBuilder<Uint8List>(
      future: widget.params.editorImage.safeByteArray(),
      builder: (context, snapshot) {
        if (!snapshot.hasData) {
          return const Scaffold(
            backgroundColor: Colors.black87,
            body: Center(
              child: CircularProgressIndicator(),
            ),
          );
        }
        final baseBytes = snapshot.data!;

        final decoded = img.decodeImage(baseBytes);
        if (decoded == null) {
          return Scaffold(
            backgroundColor: Colors.black87,
            appBar: AppBar(
              title: const Text('Animal insertion'),
              backgroundColor: Colors.black,
            ),
            body: const Center(
              child: Text(
                'Failed to decode base image.',
                style: TextStyle(color: Colors.white70),
              ),
            ),
          );
        }

        return AnimalInsertionOverlay(
          baseImageBytes: baseBytes,
          baseImageWidth: decoded.width,
          baseImageHeight: decoded.height,
          animalCutoutBytes: _animalCutoutBytes!,
          onApply: (res) => _handlePlacementApplied(res),
          onCancel: widget.onCancel,
        );
      },
    );
  }
}

