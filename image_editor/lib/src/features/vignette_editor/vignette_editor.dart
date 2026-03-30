// Dart imports:
import 'dart:async';

// Package imports:
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

// Project imports:
import 'package:image_editor/src/common/utils/async_error_runner.dart';
import 'package:image_editor/src/core/models/init_configs/vignette_editor_init_configs.dart';
import 'package:image_editor/src/features/ai_editor/common/models/history_stack.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/layout_utils.dart';
import 'package:image_editor/src/features/vignette_editor/models/vignette_adjustment_item.dart';
import 'package:image_editor/src/features/vignette_editor/models/vignette_adjustment_matrix.dart';
import 'package:image_editor/src/features/vignette_editor/utils/vignette_baker.dart';
import 'package:image_editor/src/features/vignette_editor/utils/vignette_presets.dart';
import 'package:image_editor/src/features/vignette_editor/widgets/vignette_editor_appbar.dart';
import 'package:image_editor/src/features/vignette_editor/widgets/vignette_editor_bottombar.dart';
import 'package:image_editor/src/features/vignette_editor/widgets/vignette_overlay_painter.dart';
import 'package:pro_image_editor/core/models/transform_helper.dart';
import 'package:pro_image_editor/core/utils/size_utils.dart';
import 'package:pro_image_editor/features/filter_editor/widgets/filtered_widget.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/shared/utils/file_constructor_utils.dart';
import 'package:pro_image_editor/shared/widgets/layer/layer_stack.dart';
import 'package:pro_image_editor/shared/widgets/transform/transformed_content_generator.dart';

/// Standalone vignette editor that can work with the same configs
/// as `pro_image_editor`, but only exposes vignette controls.
class VignetteEditor extends StatefulWidget {
  const VignetteEditor._({super.key, required this.initConfigs, this.editorImage, this.videoController})
    : assert(editorImage != null || videoController != null, 'Either editorImage or videoController must be provided.');

  factory VignetteEditor.memory(Uint8List byteArray, {Key? key, required VignetteEditorInitConfigs initConfigs}) {
    return VignetteEditor._(
      key: key,
      editorImage: EditorImage(byteArray: byteArray),
      initConfigs: initConfigs,
    );
  }

  factory VignetteEditor.file(dynamic file, {Key? key, required VignetteEditorInitConfigs initConfigs}) {
    return VignetteEditor._(
      key: key,
      editorImage: EditorImage(file: ensureFileInstance(file)),
      initConfigs: initConfigs,
    );
  }

  factory VignetteEditor.asset(String assetPath, {Key? key, required VignetteEditorInitConfigs initConfigs}) {
    return VignetteEditor._(
      key: key,
      editorImage: EditorImage(assetPath: assetPath),
      initConfigs: initConfigs,
    );
  }

  factory VignetteEditor.network(String networkUrl, {Key? key, required VignetteEditorInitConfigs initConfigs}) {
    return VignetteEditor._(
      key: key,
      editorImage: EditorImage(networkUrl: networkUrl),
      initConfigs: initConfigs,
    );
  }

  factory VignetteEditor.autoSource({
    Key? key,
    Uint8List? byteArray,
    dynamic file,
    String? assetPath,
    String? networkUrl,
    EditorImage? editorImage,
    ProVideoController? videoController,
    required VignetteEditorInitConfigs initConfigs,
  }) {
    return VignetteEditor._(
      key: key,
      editorImage: videoController != null
          ? null
          : editorImage ?? EditorImage(byteArray: byteArray, file: file, networkUrl: networkUrl, assetPath: assetPath),
      videoController: videoController,
      initConfigs: initConfigs,
    );
  }

  factory VignetteEditor.video(
    ProVideoController videoController, {
    Key? key,
    required VignetteEditorInitConfigs initConfigs,
  }) {
    return VignetteEditor._(key: key, videoController: videoController, initConfigs: initConfigs);
  }

  final VignetteEditorInitConfigs initConfigs;
  final EditorImage? editorImage;
  final ProVideoController? videoController;

  @override
  State<VignetteEditor> createState() => VignetteEditorState();
}

class VignetteEditorState extends State<VignetteEditor> {
  late final StreamController<void> uiStream;

  late final StreamController<void> rebuildController;

  final bottomBarScrollCtrl = ScrollController();

  late List<VignetteAdjustmentItem> vignetteAdjustmentList;

  late List<VignetteAdjustmentMatrix> vignetteAdjustmentMatrix;

  int selectedIndex = 0;

  VignetteEditorInitConfigs get initConfigs => widget.initConfigs;

  ThemeData get theme => initConfigs.theme;

  ProImageEditorConfigs get configs => initConfigs.configs;

  ProImageEditorCallbacks get callbacks => initConfigs.callbacks;

  EditorImage? get editorImage => widget.editorImage;

  ProVideoController? get videoController => widget.videoController;

  bool get isVideoEditor => videoController != null;

  Size? get mainImageSize => initConfigs.mainImageSize;

  Size? get mainBodySize => initConfigs.mainBodySize;

  get appliedFilters => initConfigs.appliedFilters;

  get appliedTuneAdjustments => initConfigs.appliedTuneAdjustments;

  double get appliedBlurFactor => initConfigs.appliedBlurFactor;

  List<Layer>? get layers => initConfigs.layers;

  TransformConfigs? get initialTransformConfigs => initConfigs.transformConfigs;

  Size editorBodySize = Size.zero;

  Object get heroTag => 'vignette_editor_hero';

  late HistoryStack<List<VignetteAdjustmentMatrix>> _history;
  bool _isProcessing = false;

  bool get canUndo => _history.canUndo;

  bool get canRedo => _history.canRedo;

  late Color vignetteColor;

  @override
  void initState() {
    super.initState();
    uiStream = StreamController.broadcast();
    rebuildController = StreamController.broadcast();
    uiStream.stream.listen((_) => rebuildController.add(null));

    var items = widget.initConfigs.vignetteAdjustmentOptions ?? vignettePresets();

    vignetteAdjustmentList = items;

    vignetteAdjustmentMatrix = [];
    for (final item in items) {
      vignetteAdjustmentMatrix.add(item.toMatrixItem());
    }
    _history = HistoryStack<List<VignetteAdjustmentMatrix>>(_cloneMatrixList(vignetteAdjustmentMatrix));

    vignetteColor = initConfigs.initialVignetteColor;
  }

  @override
  void dispose() {
    bottomBarScrollCtrl.dispose();
    uiStream.close();
    rebuildController.close();
    super.dispose();
  }

  Future<void> done() async {
    if (_isProcessing) return;
    final bytes = await editorImage?.safeByteArray();
    if (bytes == null || bytes.isEmpty) return;

    await runBusyUiFlow(
      state: this,
      setBusy: () => setState(() => _isProcessing = true),
      clearBusy: () => setState(() => _isProcessing = false),
      run: () async {
        final color = vignetteColor;
        final int red = (color.r * 255.0).round().clamp(0, 255).toInt();
        final int green = (color.g * 255.0).round().clamp(0, 255).toInt();
        final int blue = (color.b * 255.0).round().clamp(0, 255).toInt();
        final colorHex = (red << 16) | (green << 8) | blue;

        final baked = await bakeVignetteAsync(
          bytes,
          intensity: _getAdjustmentValue('intensity'),
          radius: _getAdjustmentValue('radius'),
          feather: _getAdjustmentValue('feather'),
          colorHex: colorHex,
        );
        if (baked != null && mounted) {
          await completeAndPop(
            state: this,
            context: context,
            onComplete: () => initConfigs.callbacks.onImageEditingComplete?.call(baked) ?? Future<void>.value(),
          );
        }
      },
    );
  }

  void reset() {
    _resetMatrixList();
    _history = HistoryStack<List<VignetteAdjustmentMatrix>>(_cloneMatrixList(vignetteAdjustmentMatrix));
    vignetteColor = initConfigs.initialVignetteColor;
    setState(() {});
  }

  void redo() {
    if (!_history.redo()) return;
    setState(() {
      vignetteAdjustmentMatrix = _cloneMatrixList(_history.current);
      uiStream.add(null);
    });
  }

  void undo() {
    if (!_history.undo()) return;
    setState(() {
      vignetteAdjustmentMatrix = _cloneMatrixList(_history.current);
      uiStream.add(null);
    });
  }

  void _resetMatrixList() {
    vignetteAdjustmentMatrix = vignetteAdjustmentList.map((item) => item.toMatrixItem()).toList();
  }

  void onChanged(double value) {
    var selectedItem = vignetteAdjustmentList[selectedIndex];

    int index = vignetteAdjustmentMatrix.indexWhere((item) => item.id == selectedItem.id);

    var item = VignetteAdjustmentMatrix(id: selectedItem.id, value: value, matrix: selectedItem.toMatrix(value));

    if (index >= 0) {
      vignetteAdjustmentMatrix[index] = item;
    } else {
      vignetteAdjustmentMatrix.add(item);
    }

    vignetteAdjustmentMatrix = [...vignetteAdjustmentMatrix];

    uiStream.add(null);
  }

  void onChangedStart(double value) {
    _history.push(_cloneMatrixList(vignetteAdjustmentMatrix));
  }

  void onChangedEnd(double value) {
    setState(() {});
  }

  void setVignetteColor(Color color) {
    if (vignetteColor == color) return;
    setState(() {
      vignetteColor = color;
    });
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
          child: Scaffold(
            backgroundColor: theme.scaffoldBackgroundColor,
            appBar: _buildAppBar(),
            body: _buildBody(),
            bottomNavigationBar: _buildBottomNavBar(),
          ),
        ),
      ),
    );
  }

  PreferredSizeWidget? _buildAppBar() {
    return VignetteEditorAppBar(
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
      onRedo: redo,
      onUndo: undo,
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
            if (initConfigs.showLayers && layers != null) _buildLayers(),
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

  double _getAdjustmentValue(String id) {
    final i = vignetteAdjustmentMatrix.indexWhere((e) => e.id == id);
    if (i >= 0) return vignetteAdjustmentMatrix[i].value;
    final j = vignetteAdjustmentList.indexWhere((e) => e.id == id);
    if (j >= 0) return vignetteAdjustmentList[j].defaultValue;
    return 0.5;
  }

  Widget _buildBackground() {
    return Hero(
      tag: heroTag,
      createRectTween: (begin, end) => RectTween(begin: begin, end: end),
      child: TransformedContentGenerator(
        isVideoPlayer: videoController != null,
        configs: configs,
        transformConfigs: initialTransformConfigs ?? TransformConfigs.empty(),
        child: StreamBuilder(
          stream: uiStream.stream,
          builder: (context, snapshot) {
            final bodySize = editorBodySize;
            Size size;

            if (initConfigs.mainImageSize != null && bodySize.width > 0 && bodySize.height > 0) {
              size = fitSizeWithinBounds(initConfigs.mainImageSize!, bodySize);
            } else {
              final baseSize = mainImageSize ?? mainBodySize;
              size = getValidSizeOrDefault(baseSize, editorBodySize);
            }

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
                      videoPlayer: videoController?.videoPlayer,
                      blankSize: initConfigs.mainImageSize,
                      filters: appliedFilters,
                      tuneAdjustments: vignetteAdjustmentMatrix
                          .map((v) => TuneAdjustmentMatrix(id: v.id, value: v.value, matrix: v.matrix))
                          .toList(),
                      blurFactor: appliedBlurFactor,
                    ),
                    IgnorePointer(
                      child: CustomPaint(
                        painter: VignetteOverlayPainter(
                          intensity: _getAdjustmentValue('intensity'),
                          radius: _getAdjustmentValue('radius'),
                          feather: _getAdjustmentValue('feather'),
                          color: vignetteColor,
                        ),
                      ),
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

  List<VignetteAdjustmentMatrix> _cloneMatrixList(List<VignetteAdjustmentMatrix> source) {
    return source.map((e) => e.copy()).toList(growable: false);
  }

  Widget _buildLayers() {
    return LayerStack(
      transformHelper: TransformHelper(
        mainBodySize: getValidSizeOrDefault(mainBodySize, editorBodySize),
        mainImageSize: getValidSizeOrDefault(mainImageSize, editorBodySize),
        editorBodySize: editorBodySize,
        transformConfigs: initialTransformConfigs,
      ),
      configs: configs,
      layers: layers!,
      clipBehavior: Clip.none,
      overlayColor: theme.scaffoldBackgroundColor,
    );
  }

  /// Builds the bottom navigation bar with vignette options.
  Widget? _buildBottomNavBar() {
    return VignetteEditorBottomBar(
      state: this,
      vignetteAdjustmentList: vignetteAdjustmentList,
      vignetteAdjustmentMatrix: vignetteAdjustmentMatrix,
      rebuildController: rebuildController,
      onChangedStart: onChangedStart,
      onChanged: onChanged,
      onChangedEnd: onChangedEnd,
      bottomBarScrollCtrl: bottomBarScrollCtrl,
      onSelect: (index) {
        setState(() {
          selectedIndex = index;
        });
      },
      selectedIndex: selectedIndex,
    );
  }

  @override
  void debugFillProperties(DiagnosticPropertiesBuilder properties) {
    super.debugFillProperties(properties);
    properties
      ..add(DiagnosticsProperty<VignetteEditorInitConfigs>('initConfigs', widget.initConfigs))
      ..add(DiagnosticsProperty<EditorImage?>('editorImage', widget.editorImage))
      ..add(DiagnosticsProperty<ProVideoController?>('videoController', widget.videoController))
      ..add(IntProperty('selectedIndex', selectedIndex))
      ..add(IterableProperty<VignetteAdjustmentItem>('vignetteAdjustmentList', vignetteAdjustmentList))
      ..add(IterableProperty<VignetteAdjustmentMatrix>('vignetteAdjustmentMatrix', vignetteAdjustmentMatrix))
      ..add(FlagProperty('canUndo', value: canUndo, ifTrue: 'can undo', ifFalse: 'cannot undo'))
      ..add(FlagProperty('canRedo', value: canRedo, ifTrue: 'can redo', ifFalse: 'cannot redo'))
      ..add(ColorProperty('vignetteColor', vignetteColor));
  }
}
