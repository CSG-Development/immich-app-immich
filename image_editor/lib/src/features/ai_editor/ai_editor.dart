// Dart imports:
import 'dart:async';

// Package imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';

// Project imports:
import 'package:image/image.dart' as img;

import 'package:image_editor/src/core/models/init_configs/ai_editor_init_configs.dart';
import 'package:image_editor/src/features/ai_editor/ai_editor_actions.dart';
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/ai_editor_appbar.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/ai_editor_bottombar.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/ai_modal_ui.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/model_download_dialog.dart';
import 'package:image_editor/src/features/ai_editor/object_removal/object_removal_overlay_host.dart';
import 'package:image_editor/src/features/ai_editor/common/models/history_stack.dart';
import 'package:image_editor/src/features/ai_editor/photo_enhancement/ai_photo_enhancement_page.dart';
import 'package:image_editor/src/features/ai_editor/smart_insertion/smart_insertion_flow.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/layout_utils.dart';
import 'package:logging/logging.dart';
import 'package:pro_image_editor/core/utils/size_utils.dart';
import 'package:pro_image_editor/features/filter_editor/widgets/filtered_widget.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/shared/widgets/transform/transformed_content_generator.dart';

enum _OverlayMode { none, object }

/// Standalone AI editor that can work with the same configs
/// as `pro_image_editor`, but is dedicated to AI-related tools.
///
/// For now this is a dummy page that simply shows the image and returns
/// the original bytes when the user taps "Done".
class AiEditor extends StatefulWidget {
  const AiEditor._({super.key, required this.initConfigs, required this.editorImage});

  factory AiEditor.memory(Uint8List byteArray, {Key? key, required AiEditorInitConfigs initConfigs}) {
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

  late HistoryStack<EditorImage> _history;
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

  String get _inpaintingModelPath => initConfigs.inpaintingModelPathEffective;

  Object get heroTag => 'ai_editor_hero';

  bool get canUndo => _history.canUndo;

  bool get canRedo => _history.canRedo;

  Future<T?> _openSubEditorPage<T>(Widget page, {Duration duration = const Duration(milliseconds: 300)}) {
    final subEditorStyle = configs.mainEditor.style.subEditorPage;
    return Navigator.push<T?>(
      context,
      PageRouteBuilder(
        opaque: false,
        barrierColor: subEditorStyle.barrierColor,
        barrierDismissible: subEditorStyle.barrierDismissible,
        transitionDuration: duration,
        reverseTransitionDuration: duration,
        transitionsBuilder: subEditorStyle.transitionsBuilder ??
            (context, animation, secondaryAnimation, child) {
              return FadeTransition(opacity: animation, child: child);
            },
        pageBuilder: (context, animation, secondaryAnimation) {
          if (!subEditorStyle.requireReposition) return page;

          return SafeArea(
            child: Stack(
              fit: StackFit.expand,
              children: [
                Positioned(
                  top: subEditorStyle.positionTop,
                  left: subEditorStyle.positionLeft,
                  right: subEditorStyle.positionRight,
                  bottom: subEditorStyle.positionBottom,
                  child: Center(
                    child: Container(
                      width: subEditorStyle.enforceSizeFromMainEditor ? MediaQuery.of(context).size.width : null,
                      height: subEditorStyle.enforceSizeFromMainEditor ? MediaQuery.of(context).size.height : null,
                      clipBehavior: Clip.hardEdge,
                      decoration: BoxDecoration(borderRadius: subEditorStyle.borderRadius),
                      child: page,
                    ),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  @override
  void initState() {
    super.initState();
    uiStream = StreamController<void>.broadcast();
    _history = HistoryStack<EditorImage>(widget.editorImage);
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
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('AI tools are currently unavailable on web.')),
      );
    }
    return false;
  }

  Future<void> _handleObjectRemoval() async {
    if (_isProcessing) return;
    if (!_ensureAiToolsAvailable()) return;

    setState(() {
      _overlayMode = _OverlayMode.object;
    });
  }

  Future<void> _handleSmartInsertion() async {
    if (_isProcessing) return;
    if (!_ensureAiToolsAvailable()) return;

    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) {
      return;
    }
    final pickedImageBytes = await picked.readAsBytes();
    if (!mounted || pickedImageBytes.isEmpty) return;

    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (ctx) {
          return SmartInsertionFlow(
            params: SmartInsertionParams(
              editorImage: editorImage,
              actions: _actions,
              backgroundRemovalService: _actions.backgroundRemovalService,
              backgroundEffectMode: BackgroundEffectMode.remove,
              inpaintingModelPathOrUrl: initConfigs.inpaintingModelPathEffective,
            ),
            pickedImageBytes: pickedImageBytes,
            onCompleted: (resultBytes) async {
              final newImage = EditorImage(byteArray: resultBytes);
              _history.push(newImage);
              uiStream.add(null);
              if (Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop();
              }
            },
            onCancel: () {
              if (Navigator.of(ctx).canPop()) {
                Navigator.of(ctx).pop();
              }
            },
          );
        },
      ),
    );
  }

  Future<void> _handleEnhance() async {
    if (_isProcessing) return;
    if (!_ensureAiToolsAvailable()) return;

    final bytes = await editorImage.safeByteArray();
    if (!mounted || bytes.isEmpty) return;

    final result = await _openSubEditorPage<Uint8List?>(
      AiPhotoEnhancementPage(initConfigs: initConfigs, initialImageBytes: bytes),
    );

    if (!mounted || result == null || result.isEmpty) {
      return;
    }

    final newImage = EditorImage(byteArray: result);
    _history.push(newImage);
    uiStream.add(null);
  }

  Future<void> _runObjectRemoval(img.Image mask) async {
    setState(() {
      _overlayMode = _OverlayMode.none;
    });
    if (_isProcessing) return;
    if (!_ensureAiToolsAvailable()) return;
    final ok = await showModelDownloadDialog(
      context,
      modelPathOrUrl: _inpaintingModelPath,
      modelName: 'Smart removal',
    );
    if (!ok || !mounted) return;

    setState(() {
      _isProcessing = true;
    });
    try {
      final bytes = await editorImage.safeByteArray();
      if (bytes.isEmpty || !mounted) return;

      final removed = await _actions.removeObjectsInpaintOnly(bytes, mask);
      if (!mounted) return;
      if (listEquals(removed, bytes)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Failed to remove object (check that lama_fp32.onnx is available).'),
          ),
        );
        return;
      }

      _history.push(EditorImage(byteArray: removed));
      uiStream.add(null);

      final artifactMask = await _actions.detectArtifactMask(removed, mask);
      if (!mounted || artifactMask == null) return;

      final applyArtifacts = await _askApplyArtifactCleanup();
      if (!mounted || applyArtifacts != true) return;

      final cleaned = await _actions.removeArtifacts(removed, mask, artifactMask);
      if (!mounted) return;
      if (!listEquals(cleaned, removed)) {
        _history.push(EditorImage(byteArray: cleaned));
        uiStream.add(null);
      }
    } catch (e) {
      _log.warning('Smart removal failed: $e');
    } finally {
      if (mounted) {
        setState(() {
          _isProcessing = false;
        });
      }
    }
  }

  Future<bool?> _askApplyArtifactCleanup() async {
    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Artifacts detected'),
        content: const Text(
          'Try to remove detected artifacts automatically?\n\n'
          'Warning: automatic artifact cleanup can be unpredictable and may make '
          'the result worse in some cases.',
          style: AiModalUi.contentStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
  }

  void _closeOverlay() {
    setState(() {
      _overlayMode = _OverlayMode.none;
    });
  }

  List<Widget> _buildOverlayHosts() {
    return [
      if (_overlayMode == _OverlayMode.object)
        ObjectRemovalOverlayHost(
          editorImage: editorImage,
          backgroundRemovalService: _actions.backgroundRemovalService,
          onApply: _runObjectRemoval,
          onCancel: _closeOverlay,
        ),
    ];
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
                    : AiEditorBottomBar(
                        onObjectRemoval: _handleObjectRemoval,
                        onEnhance: _handleEnhance,
                        onSmartInsertion: _handleSmartInsertion,
                        isBusy: _isProcessing,
                      ),
              ),
              ..._buildOverlayHosts(),
            ],
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget? _buildAppBar() {
    return AiEditorAppBar(
      theme: theme,
      canRedo: canRedo,
      canUndo: canUndo,
      isBusy: _isProcessing,
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
                child: const Center(child: CircularProgressIndicator()),
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
    if (initConfigs.mainImageSize != null && bodySize.width > 0 && bodySize.height > 0) {
      final imgSize = initConfigs.mainImageSize!;
      return fitSizeWithinBounds(imgSize, bodySize);
    }

    final baseSize = mainImageSize ?? mainBodySize;
    return getValidSizeOrDefault(baseSize, editorBodySize);
  }
}

