// Dart imports:
import 'dart:async';
import 'dart:typed_data';

// Package imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Project imports:
import 'package:image/image.dart' as img;

import 'package:image_editor/src/core/models/init_configs/ai_editor_init_configs.dart';
import 'package:image_editor/src/features/ai_editor/ai_editor_actions.dart';
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/ai_editor_appbar.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/ai_editor_bottombar.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/model_download_dialog.dart';
import 'package:image_editor/src/features/ai_editor/object_removal/object_removal_overlay_host.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/layout_utils.dart';
import 'package:logging/logging.dart';
import 'package:pro_image_editor/core/utils/size_utils.dart';
import 'package:pro_image_editor/features/filter_editor/widgets/filtered_widget.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/shared/widgets/transform/transformed_content_generator.dart';

/// Simple in-memory history for `EditorImage` states used by the AI editor.
class _EditorHistory {
  _EditorHistory(EditorImage initial)
      : _items = [initial],
        _index = 0;

  final List<EditorImage> _items;
  int _index;

  EditorImage get current => _items[_index];

  bool get canUndo => _index > 0;
  bool get canRedo => _index < _items.length - 1;

  bool undo() {
    if (!canUndo) return false;
    _index -= 1;
    return true;
  }

  bool redo() {
    if (!canRedo) return false;
    _index += 1;
    return true;
  }

  /// Pushes a new image state and discards any redo history.
  void push(EditorImage image) {
    if (_index < _items.length - 1) {
      _items.removeRange(_index + 1, _items.length);
    }
    _items.add(image);
    _index = _items.length - 1;
  }
}

enum _OverlayMode { none, object }

/// Standalone AI editor that can work with the same configs
/// as `pro_image_editor`, but is dedicated to AI-related tools.
///
/// For now this is a dummy page that simply shows the image and returns
/// the original bytes when the user taps "Done".
class AiEditor extends StatefulWidget {
  const AiEditor._({
    super.key,
    required this.initConfigs,
    required this.editorImage,
  });

  factory AiEditor.memory(
    Uint8List byteArray, {
    Key? key,
    required AiEditorInitConfigs initConfigs,
  }) {
    return AiEditor._(
      key: key,
      editorImage: EditorImage(byteArray: byteArray),
      initConfigs: initConfigs,
    );
  }

  final AiEditorInitConfigs initConfigs;
  final EditorImage editorImage;

  @override
  State<AiEditor> createState() => AiEditorState();
}

class AiEditorState extends State<AiEditor> {
  static final Logger _log = Logger('AiEditor');
  late final StreamController<void> uiStream;
  Size editorBodySize = Size.zero;

  late _EditorHistory _history;
  EditorImage get editorImage => _history.current;

  late final AiEditorActions _actions;
  bool _isProcessing = false;
  _OverlayMode _overlayMode = _OverlayMode.none;

  bool get _hasOverlay => _overlayMode != _OverlayMode.none;

  AiEditorInitConfigs get initConfigs => widget.initConfigs;

  ThemeData get theme => initConfigs.theme;

  ProImageEditorConfigs get configs => initConfigs.configs;

  ProImageEditorCallbacks get callbacks => initConfigs.callbacks;

  Size? get mainImageSize => initConfigs.mainImageSize;

  Size? get mainBodySize => initConfigs.mainBodySize;

  get appliedFilters => initConfigs.appliedFilters;

  get appliedTuneAdjustments => initConfigs.appliedTuneAdjustments;

  double get appliedBlurFactor => initConfigs.appliedBlurFactor;

  TransformConfigs? get initialTransformConfigs => initConfigs.transformConfigs;

  String get _backgroundModelPath => initConfigs.backgroundModelPathEffective;

  String get _inpaintingModelPath => initConfigs.inpaintingModelPathEffective;

  String get _fastdvdnetModelPath => initConfigs.fastdvdnetModelPathEffective;

  Object get heroTag => 'ai_editor_hero';

  bool get canUndo => _history.canUndo;

  bool get canRedo => _history.canRedo;

  Future<void> _runImageProcessing({
    required String modelPathOrUrl,
    required String modelName,
    required String emptyBytesMessage,
    required String failureMessage,
    required Future<Uint8List> Function(Uint8List bytes) process,
    String? successMessage,
    String? sameBytesErrorMessage,
    bool ensureAiTools = true,
    String? debugTag,
  }) async {
    if (_isProcessing) return;
    if (ensureAiTools && !_ensureAiToolsAvailable()) return;

    final ok = await showModelDownloadDialog(
      context,
      modelPathOrUrl: modelPathOrUrl,
      modelName: modelName,
    );
    if (!ok || !mounted) return;

    setState(() {
      _isProcessing = true;
    });

    try {
      final bytes = await editorImage.safeByteArray();
      if (bytes.isEmpty) {
        return;
      }

      if (kDebugMode && debugTag != null) {
        _log.fine('[$debugTag] Input bytes length: ${bytes.length}');
      }

      final processed = await process(bytes);

      if (!mounted) return;

      if (kDebugMode && debugTag != null) {
        _log.fine('[$debugTag] Processed bytes length: ${processed.length}');
      }

      if (sameBytesErrorMessage != null && listEquals(processed, bytes)) {
        return;
      }

      final newImage = EditorImage(byteArray: processed);
      _history.push(newImage);
      uiStream.add(null);

      // Intentionally no automatic toast/snackbar here; host app can surface
      // success via its own callbacks if desired.
    } catch (e) {
      if (kDebugMode) {
        _log.warning('$modelName failed: $e');
      }
      if (!mounted) return;
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    uiStream = StreamController<void>.broadcast();
    _history = _EditorHistory(widget.editorImage);
    _actions = AiEditorActions(initConfigs: initConfigs);
  }

  @override
  void dispose() {
    _actions.dispose();
    uiStream.close();
    super.dispose();
  }

  Future<void> done() async {
    final bytes = await editorImage.safeByteArray();
    if (bytes.isEmpty) return;

    await initConfigs.callbacks.onImageEditingComplete?.call(bytes);
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _undo() {
    if (!canUndo) return;
    setState(() {
      _history.undo();
    });
    uiStream.add(null);
  }

  void _redo() {
    if (!canRedo) return;
    setState(() {
      _history.redo();
    });
    uiStream.add(null);
  }

  bool _ensureAiToolsAvailable() {
    if (!kIsWeb) {
      return true;
    }
    return false;
  }

  Future<void> _runBackgroundEffect(
    BackgroundEffectMode mode,
    String successMessage,
  ) async {
    return _runImageProcessing(
      modelPathOrUrl: _backgroundModelPath,
      modelName: 'Background removal',
      emptyBytesMessage: 'No image data available for background removal.',
      failureMessage: 'Failed to remove background.',
      sameBytesErrorMessage:
          'Failed to apply background effect (device may be low on memory).',
      successMessage: successMessage,
      ensureAiTools: true,
      debugTag: 'BG',
      process: (bytes) => _actions.applyBackground(bytes, mode: mode),
    );
  }

  Future<void> _runFastDenoise() async {
    return _runImageProcessing(
      modelPathOrUrl: _fastdvdnetModelPath,
      modelName: 'Denoise',
      emptyBytesMessage: 'No image data available for denoising.',
      failureMessage: 'Failed to denoise image.',
      successMessage: 'Noise reduced.',
      ensureAiTools: true,
      debugTag: 'FDN',
      process: _actions.denoiseFastdvdnet,
    );
  }

  Future<void> _handleBlurBackground() {
    return _runBackgroundEffect(
      BackgroundEffectMode.blur,
      'Background blurred.',
    );
  }

  Future<void> _handleObjectRemoval() async {
    if (_isProcessing) return;
    if (!_ensureAiToolsAvailable()) return;

    setState(() {
      _overlayMode = _OverlayMode.object;
    });
  }

  Future<void> _runObjectRemoval(img.Image mask) async {
    setState(() {
      _overlayMode = _OverlayMode.none;
    });

    await _runImageProcessing(
      modelPathOrUrl: _inpaintingModelPath,
      modelName: 'Object removal',
      emptyBytesMessage: 'No image data available for object removal.',
      failureMessage: 'Failed to remove object.',
      sameBytesErrorMessage:
          'Failed to remove object (check that lama_fp32.onnx is available).',
      successMessage: 'Removed.',
      ensureAiTools: false,
      debugTag: 'OR',
      process: (bytes) => _actions.removeObjects(bytes, mask),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: theme.copyWith(tooltipTheme: theme.tooltipTheme.copyWith(preferBelow: true)),
      child: AnnotatedRegion<SystemUiOverlayStyle>(
        value: theme.appBarTheme.systemOverlayStyle ?? SystemUiOverlayStyle.light,
        child: SafeArea(
          top: true,
          bottom: true,
          left: true,
          right: true,
          child: Stack(
            children: [
              Scaffold(
                backgroundColor: theme.scaffoldBackgroundColor,
                appBar: _hasOverlay ? null : _buildAppBar(),
                body: _buildBody(),
                bottomNavigationBar: _hasOverlay
                    ? null
                    : AiEditorBottombar(
                        onBlurBackground: _handleBlurBackground,
                        onDenoise: _runFastDenoise,
                        onObjectRemoval: _handleObjectRemoval,
                      ),
              ),
              if (_overlayMode == _OverlayMode.object)
                ObjectRemovalOverlayHost(
                  editorImage: editorImage,
                  onApply: _runObjectRemoval,
                  onCancel: () {
                    setState(() {
                      _overlayMode = _OverlayMode.none;
                    });
                  },
                ),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget? _buildAppBar() {
    return AiEditorAppbar(
      theme: theme,
      canRedo: canRedo,
      canUndo: canUndo,
      onClose: () {
        if (Navigator.of(context).canPop()) {
          Navigator.of(context).pop();
        }
      },
      onDone: done,
      onRedo: _redo,
      onUndo: _undo,
    );
  }

  Widget _buildBody() {
    return LayoutBuilder(
      builder: (context, constraints) {
        editorBodySize = constraints.biggest;
        return Stack(
          alignment: Alignment.center,
          fit: StackFit.expand,
          children: [
            _buildBackground(),
            if (_isProcessing)
              Container(
                color: Colors.black26,
                child: const Center(
                  child: CircularProgressIndicator(),
                ),
              ),
          ],
        );
      },
    );
  }

  Widget _buildBackground() {
    return Hero(
      tag: heroTag,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      child: TransformedContentGenerator(
        isVideoPlayer: false,
        configs: configs,
        transformConfigs: initialTransformConfigs ?? TransformConfigs.empty(),
        child: StreamBuilder(
          stream: uiStream.stream,
          builder: (context, snapshot) {
            final bodySize = editorBodySize;
            final size = _computeImageDisplaySize(bodySize);

            return Center(
              child: SizedBox(
                width: size.width,
                height: size.height,
                child: Stack(
                  fit: StackFit.expand,
                  alignment: Alignment.center,
                  children: [
                    FilteredWidget(
                      width: size.width,
                      height: size.height,
                      configs: configs,
                      image: editorImage,
                      videoPlayer: null,
                      blankSize: initConfigs.mainImageSize,
                      filters: appliedFilters,
                      tuneAdjustments: appliedTuneAdjustments,
                      blurFactor: appliedBlurFactor,
                    ),
                  ],
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Size _computeImageDisplaySize(Size bodySize) {
    if (initConfigs.mainImageSize != null &&
        bodySize.width > 0 &&
        bodySize.height > 0) {
      final imgSize = initConfigs.mainImageSize!;
      return fitSizeWithinBounds(imgSize, bodySize);
    }

    final baseSize = mainImageSize ?? mainBodySize;
    return getValidSizeOrDefault(baseSize, editorBodySize);
  }
}
