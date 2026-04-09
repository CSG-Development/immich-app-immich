import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/common/widgets/image_editor_translation_scope.dart';
import 'package:image_editor/src/features/ai_editor/ai_editor_actions.dart';
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/model_download_dialog.dart';
import 'package:image_editor/src/features/ai_editor/smart_insertion/smart_insertion_cutout_overlay.dart';
import 'package:image_editor/src/features/ai_editor/smart_insertion/smart_insertion_overlay.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

class SmartInsertionParams {
  SmartInsertionParams({
    required this.editorImage,
    required this.actions,
    required this.backgroundRemovalService,
    required this.backgroundEffectMode,
    required this.inpaintingModelPathOrUrl,
  });

  final EditorImage editorImage;
  final AiEditorActions actions;
  final BackgroundRemovalService backgroundRemovalService;
  final BackgroundEffectMode backgroundEffectMode;
  final String inpaintingModelPathOrUrl;
}

class SmartInsertionFlow extends StatefulWidget {
  const SmartInsertionFlow({
    super.key,
    required this.params,
    required this.onCompleted,
    required this.onCancel,
    required this.pickedImageBytes,
  });

  final SmartInsertionParams params;
  final void Function(Uint8List resultBytes) onCompleted;
  final VoidCallback onCancel;
  final Uint8List pickedImageBytes;

  @override
  State<SmartInsertionFlow> createState() => _SmartInsertionFlowState();
}

class _SmartInsertionFlowState extends State<SmartInsertionFlow> {
  Uint8List? _cutoutBytes;
  late final BackgroundRemovalService _cutoutBackgroundRemovalService;

  @override
  void initState() {
    super.initState();
    final baseService = widget.params.backgroundRemovalService;
    _cutoutBackgroundRemovalService = BackgroundRemovalService(
      modelPathOrUrl: baseService.modelPathOrUrl,
      // Higher input resolution gives smoother, less stair-stepped masks.
      inputWidth: 512,
      inputHeight: 512,
      imageInputName: baseService.imageInputName,
      outputName: baseService.outputName,
      rescaleFactor: baseService.rescaleFactor,
      imageMean: baseService.imageMean,
      imageStd: baseService.imageStd,
    );
  }

  Future<void> _handlePlacementApplied(SmartInsertionResult result) async {
    final baseBytes = await widget.params.editorImage.safeByteArray();
    if (!mounted) return;

    final composed = await widget.params.actions.insertSmart(
      baseImageBytes: baseBytes,
      cutoutBytes: result.cutoutBytes,
      placementMask: result.placementMask,
    );
    if (!mounted) return;
    widget.onCompleted(composed);
  }

  Future<bool> _ensureRequiredModelsReady() async {
    final segmentationReady = await showModelDownloadDialog(
      context,
      modelPathOrUrl: _cutoutBackgroundRemovalService.modelPathOrUrl,
      modelName: ImageEditorTranslationScope.text(context, 'image_editor.ai.smart_insertion', 'Smart insertion'),
    );
    if (!segmentationReady) return false;

    final inpaintingReady = await showModelDownloadDialog(
      context,
      modelPathOrUrl: widget.params.inpaintingModelPathOrUrl,
      modelName: ImageEditorTranslationScope.text(
        context,
        'image_editor.ai.smart_insertion_inpaint',
        'Smart insertion inpaint',
      ),
    );
    return inpaintingReady;
  }

  @override
  void dispose() {
    _cutoutBackgroundRemovalService.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: widget.params.editorImage.safeByteArray(),
      builder: (context, baseSnapshot) {
        if (!baseSnapshot.hasData) {
          return const Scaffold(
            backgroundColor: Colors.black87,
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final baseBytes = baseSnapshot.data!;
        final baseDecoded = img.decodeImage(baseBytes);
        final pickedDecoded = img.decodeImage(widget.pickedImageBytes);
        if (baseDecoded == null || pickedDecoded == null) {
          return Scaffold(
            backgroundColor: Colors.black87,
            appBar: AppBar(
              title: Text(
                ImageEditorTranslationScope.text(context, 'image_editor.ai.smart_insertion', 'Smart insertion'),
              ),
              backgroundColor: Colors.black,
            ),
            body: Center(
              child: Text(
                ImageEditorTranslationScope.text(
                  context,
                  'image_editor.failed_to_decode_image',
                  'Failed to decode image.',
                ),
                style: TextStyle(color: Colors.white70),
              ),
            ),
          );
        }

        final baseTheme = Theme.of(context);
        final darkTheme = baseTheme.copyWith(
          scaffoldBackgroundColor: Colors.black87,
          appBarTheme: baseTheme.appBarTheme.copyWith(
            backgroundColor: Colors.black,
            foregroundColor: Colors.white,
          ),
        );

        if (_cutoutBytes == null) {
          return Theme(
            data: darkTheme,
            child: SmartInsertionCutoutOverlay(
              imageBytes: widget.pickedImageBytes,
              imageWidth: pickedDecoded.width,
              imageHeight: pickedDecoded.height,
              backgroundRemovalService: _cutoutBackgroundRemovalService,
              ensureModelReady: _ensureRequiredModelsReady,
              onApply: (cutoutBytes) {
                setState(() {
                  _cutoutBytes = cutoutBytes;
                });
              },
              onCancel: widget.onCancel,
            ),
          );
        }

        return Theme(
          data: darkTheme,
          child: SmartInsertionOverlay(
            baseImageBytes: baseBytes,
            baseImageWidth: baseDecoded.width,
            baseImageHeight: baseDecoded.height,
            cutoutBytes: _cutoutBytes!,
            onApply: (res) => _handlePlacementApplied(res),
            onCancel: widget.onCancel,
          ),
        );
      },
    );
  }
}
