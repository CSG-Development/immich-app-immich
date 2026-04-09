import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:image_editor/src/common/utils/async_error_runner.dart';
import 'package:image_editor/src/common/utils/platform_tooltip.dart';
import 'package:image_editor/src/common/widgets/editor_action_app_bar.dart';
import 'package:image_editor/src/common/widgets/image_editor_translation_scope.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/layout_utils.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/core/models/layers/layer_interaction.dart';

enum WatermarkMode { text, logo, both }

enum WatermarkPosition { topLeft, topRight, bottomLeft, bottomRight, center, patternGrid }

/// Watermark UI with a local preview; the main editor gets a [WidgetLayer] only
/// on **Apply**, matching the official sticker flow (`setLayer` → one shot)
/// rather than mutating the layer on every keystroke (which breaks history /
/// background capture). See [pro_image_editor examples](https://github.com/hm21/pro_image_editor/tree/stable/example/lib).
class WatermarkEditor extends StatefulWidget {
  const WatermarkEditor._({
    super.key,
    required this.imageBytes,
    required this.editor,
    required this.onDone,
    required this.theme,
    required this.mainImageSize,
    required this.mainBodySize,
  });

  factory WatermarkEditor.memory(
    Uint8List imageBytes, {
    Key? key,
    ProImageEditorState? editor,
    required ThemeData theme,
    required Size mainImageSize,
    required Size mainBodySize,
    required FutureOr<void> Function() onDone,
  }) {
    return WatermarkEditor._(
      key: key,
      imageBytes: imageBytes,
      editor: editor,
      onDone: onDone,
      theme: theme,
      mainImageSize: mainImageSize,
      mainBodySize: mainBodySize,
    );
  }

  final Uint8List imageBytes;
  final ProImageEditorState? editor;
  final FutureOr<void> Function() onDone;
  final ThemeData theme;

  /// Sizes from `pro_image_editor` used for fit/placement calculations.
  final Size mainImageSize;
  final Size mainBodySize;

  @override
  State<WatermarkEditor> createState() => _WatermarkEditorState();
}

class _WatermarkEditorState extends State<WatermarkEditor> {
  static const String _watermarkGroupId = 'custom-watermark-layer';
  final _textController = TextEditingController();
  final _watermarkFocus = FocusNode();
  static const List<int> _colorPresets = <int>[0xFFFFFF, 0x000000, 0xFACC15, 0x22C55E, 0x38BDF8, 0xA78BFA, 0xEF4444];

  WatermarkMode _mode = WatermarkMode.text;
  WatermarkPosition _position = WatermarkPosition.bottomRight;
  String _watermarkText = 'Your Name';
  String _t(String key, String fallback) => ImageEditorTranslationScope.text(context, key, fallback);

  Uint8List? _watermarkLogoBytes;
  int _textColorRgb = 0xFFFFFF;
  double _opacity = 0.5;
  double _sizeFactor = 1.0;
  double _angleDegrees = 0.0;

  WidgetLayer? _initialLayer;
  bool _isApplying = false;
  bool _didInitLocalizedDefaults = false;

  void _onWatermarkTextControllerChanged() {
    final v = _textController.text;
    if (v == _watermarkText) return;
    setState(() => _watermarkText = v);
  }

  @override
  void initState() {
    super.initState();
    _textController.addListener(_onWatermarkTextControllerChanged);
    _textController.text = _watermarkText;
    if (kIsWeb && _mode != WatermarkMode.text) {
      _mode = WatermarkMode.text;
    }
    // Remove any existing watermark from the main stack so the user edits in
    // this page's preview only; we add one fresh layer on Apply (sticker-style).
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final existing = _findCurrentWatermarkLayer();
      if (existing != null) {
        _initialLayer = existing;
        widget.editor?.removeLayer(existing, blockCaptureScreenshot: true);
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_didInitLocalizedDefaults) {
      return;
    }
    _didInitLocalizedDefaults = true;
    _watermarkText = _t('image_editor.watermark.default_text', 'Your Name');
    _textController.text = _watermarkText;
  }

  @override
  void dispose() {
    _textController.removeListener(_onWatermarkTextControllerChanged);
    _watermarkFocus.dispose();
    _textController.dispose();
    super.dispose();
  }

  void _unfocusWatermarkField() {
    _watermarkFocus.unfocus();
  }

  /// Axis-aligned bounds of [w]×[h] after rotation by [angleDegrees].
  static Size _rotatedAabbSize(double w, double h, double angleDegrees) {
    if (w <= 0 || h <= 0) return Size.zero;
    final r = angleDegrees * math.pi / 180.0;
    final c = math.cos(r).abs();
    final s = math.sin(r).abs();
    return Size(w * c + h * s, w * s + h * c);
  }

  /// Prefer live sizes from the main editor so layer placement matches the
  /// canvas **after** IME/keyboard layout (stale [mainBodySize] from route
  /// open misaligns watermark when Apply unfocuses first).
  Size _liveBodySize(ProImageEditorState editor) {
    final s = editor.sizesManager.bodySize;
    if (s.width > 0 && s.height > 0) return s;
    return widget.mainBodySize;
  }

  Size _liveImageSize(ProImageEditorState editor) {
    final s = editor.sizesManager.decodedImageSize;
    if (s.width > 0 && s.height > 0) return s;
    return widget.mainImageSize;
  }

  Future<void> _pickLogo() async {
    _unfocusWatermarkField();
    if (kIsWeb) return;
    final picker = ImagePicker();
    final picked = await picker.pickImage(source: ImageSource.gallery);
    if (picked == null) return;

    final bytes = await picked.readAsBytes();
    if (!mounted || bytes.isEmpty) return;

    final decoded = img.decodeImage(bytes);
    if (decoded == null) return;
    setState(() {
      _watermarkLogoBytes = Uint8List.fromList(bytes);
    });
  }

  void _removeLogo() {
    _unfocusWatermarkField();
    setState(() {
      _watermarkLogoBytes = null;
    });
  }

  WidgetLayer? _findCurrentWatermarkLayer() {
    final editor = widget.editor;
    if (editor == null) return null;
    for (final layer in editor.activeLayers.reversed) {
      if (layer.groupId == _watermarkGroupId && layer is WidgetLayer) {
        return layer;
      }
    }
    return null;
  }

  bool get _hasRenderableContent {
    final hasText = _mode != WatermarkMode.logo && _watermarkText.trim().isNotEmpty;
    final hasLogo = _mode != WatermarkMode.text && _watermarkLogoBytes != null;
    return hasText || hasLogo;
  }

  /// Identity for [ValueKey] so the editor layer subtree is not element-reused
  /// with stale [Text] painting when only the string (or other visuals) change.
  String get _watermarkVisualIdentity {
    final logo = _watermarkLogoBytes;
    final logoTag = logo == null ? '0' : '${logo.length}_${logo.hashCode}';
    return 'wm|$_watermarkText|$_mode|$_position|'
        '${_opacity.toStringAsFixed(4)}|${_sizeFactor.toStringAsFixed(4)}|'
        '${_angleDegrees.toStringAsFixed(2)}|$_textColorRgb|$logoTag';
  }

  TextStyle _watermarkTextStyle(double textFont) {
    return TextStyle(
      color: Color(0xFF000000 | _textColorRgb),
      fontWeight: FontWeight.w600,
      fontSize: textFont,
      height: 1,
    );
  }

  /// Unrotated width/height of the watermark tile (for pattern grid spacing).
  Size _intrinsicTileSize(Size canvasSize, TextScaler textScaler) {
    final hasText = _mode != WatermarkMode.logo && _watermarkText.trim().isNotEmpty;
    final hasLogo = _mode != WatermarkMode.text && _watermarkLogoBytes != null;
    if (!hasText && !hasLogo) return Size.zero;

    final longSide = canvasSize.longestSide;
    final textFont = longSide * (_mode == WatermarkMode.both ? 0.026 : 0.032) * _sizeFactor;
    final logoBox = longSide * (_mode == WatermarkMode.both ? 0.045 : 0.06) * _sizeFactor;
    final gap = longSide * 0.012 * _sizeFactor;

    if (_mode == WatermarkMode.text || !hasLogo) {
      final tp = TextPainter(
        text: TextSpan(text: _watermarkText, style: _watermarkTextStyle(textFont)),
        textDirection: TextDirection.ltr,
        textScaler: textScaler,
      )..layout();
      return Size(tp.width, tp.height);
    }
    if (_mode == WatermarkMode.logo || !hasText) {
      return Size(logoBox, logoBox);
    }
    final tp = TextPainter(
      text: TextSpan(text: _watermarkText, style: _watermarkTextStyle(textFont)),
      textDirection: TextDirection.ltr,
      textScaler: textScaler,
    )..layout();
    final rowW = logoBox + gap + tp.width;
    final rowH = math.max(logoBox, tp.height);
    return Size(rowW, rowH);
  }

  Widget _buildWatermarkContentForSize(Size canvasSize, {TextScaler textScaler = TextScaler.noScaling}) {
    final hasText = _mode != WatermarkMode.logo && _watermarkText.trim().isNotEmpty;
    final hasLogo = _mode != WatermarkMode.text && _watermarkLogoBytes != null;
    if (!hasText && !hasLogo) return const SizedBox.shrink();

    final longSide = canvasSize.longestSide;
    final textFont = longSide * (_mode == WatermarkMode.both ? 0.026 : 0.032) * _sizeFactor;
    final logoBox = longSide * (_mode == WatermarkMode.both ? 0.045 : 0.06) * _sizeFactor;
    final gap = longSide * 0.012 * _sizeFactor;
    final edgeInset = longSide * 0.012;

    Widget item;
    if (_mode == WatermarkMode.text || !hasLogo) {
      item = Text(
        _watermarkText,
        key: ValueKey<String>(_watermarkText),
        style: _watermarkTextStyle(textFont),
      );
    } else if (_mode == WatermarkMode.logo || !hasText) {
      item = SizedBox(
        width: logoBox,
        height: logoBox,
        child: Image.memory(_watermarkLogoBytes!, fit: BoxFit.contain),
      );
    } else {
      item = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            width: logoBox,
            height: logoBox,
            child: Image.memory(_watermarkLogoBytes!, fit: BoxFit.contain),
          ),
          SizedBox(width: gap),
          Text(
            _watermarkText,
            key: ValueKey<String>(_watermarkText),
            style: _watermarkTextStyle(textFont),
          ),
        ],
      );
    }

    item = Opacity(
      opacity: _opacity.clamp(0.0, 1.0),
      child: Transform.rotate(angle: _angleDegrees * 3.141592653589793 / 180.0, child: item),
    );

    if (_position == WatermarkPosition.patternGrid) {
      final intrinsic = _intrinsicTileSize(canvasSize, textScaler);
      final aabb = _rotatedAabbSize(intrinsic.width, intrinsic.height, _angleDegrees);
      final minGap = longSide * 0.014 * _sizeFactor;
      final stepX = math.max(
        canvasSize.width * (_mode == WatermarkMode.both ? 0.28 : 0.22),
        aabb.width + minGap,
      );
      final stepY = math.max(
        canvasSize.height * (_mode == WatermarkMode.both ? 0.20 : 0.16),
        aabb.height + minGap,
      );
      final cellsX = (canvasSize.width / stepX).ceil() + 2;
      final cellsY = (canvasSize.height / stepY).ceil() + 2;
      return SizedBox(
        width: canvasSize.width,
        height: canvasSize.height,
        child: Stack(
          children: [
            for (int y = -1; y < cellsY; y++)
              for (int x = -1; x < cellsX; x++) Positioned(left: x * stepX, top: y * stepY, child: item),
          ],
        ),
      );
    }

    final alignment = switch (_position) {
      WatermarkPosition.topLeft => Alignment.topLeft,
      WatermarkPosition.topRight => Alignment.topRight,
      WatermarkPosition.bottomLeft => Alignment.bottomLeft,
      WatermarkPosition.bottomRight => Alignment.bottomRight,
      WatermarkPosition.center => Alignment.center,
      WatermarkPosition.patternGrid => Alignment.topLeft,
    };

    return SizedBox(
      width: canvasSize.width,
      height: canvasSize.height,
      child: Padding(
        padding: EdgeInsets.all(edgeInset),
        child: Align(alignment: alignment, child: item),
      ),
    );
  }

  void _removeWorkingLayer() {
    final current = _findCurrentWatermarkLayer();
    if (current != null) {
      widget.editor?.removeLayer(current, blockCaptureScreenshot: true);
    }
  }

  /// Commits the watermark to the main editor (call from **Apply** only).
  ///
  /// Matches the sticker example: one [WidgetLayer] add after the user
  /// finishes, instead of updating the stack on every control change.
  void _rebuildLayer() {
    final editor = widget.editor;
    if (editor == null) return;

    if (!_hasRenderableContent) {
      _removeWorkingLayer();
      return;
    }

    final bodySize = _liveBodySize(editor);
    final imageSize = _liveImageSize(editor);
    final fit = fitSizeWithinBounds(imageSize, bodySize);
    final initWidth = editor.configs.stickerEditor.initWidth;
    final layerCanvas = Size(initWidth, initWidth * (fit.height / fit.width));
    final topLeft = Offset((bodySize.width - fit.width) / 2, (bodySize.height - fit.height) / 2);
    final fractional = editor.configs.stickerEditor.layerFractionalOffset;
    final desiredOffsetInBody = Offset(topLeft.dx - fractional.dx * fit.width, topLeft.dy - fractional.dy * fit.height);
    final offset = Offset(
      desiredOffsetInBody.dx - bodySize.width / 2,
      desiredOffsetInBody.dy - bodySize.height / 2,
    );
    final scale = fit.width / initWidth;
    final textScaler = mounted ? MediaQuery.textScalerOf(context) : TextScaler.noScaling;

    final painted = KeyedSubtree(
      key: ValueKey<String>(_watermarkVisualIdentity),
      child: _buildWatermarkContentForSize(layerCanvas, textScaler: textScaler),
    );

    final layer = WidgetLayer(
      widget: painted,
      offset: offset,
      scale: scale,
      interaction: LayerInteraction.fromDefaultValue(false),
      groupId: _watermarkGroupId,
      meta: const {'type': 'watermark'},
    );

    _removeWorkingLayer();
    editor.addLayer(
      layer,
      blockSelectLayer: true,
      blockCaptureScreenshot: true,
      autoCorrectZoomOffset: false,
      autoCorrectZoomScale: false,
    );
  }

  Future<void> _notifyDone() async {
    await widget.onDone();
  }

  Future<void> _handleApply() async {
    if (_isApplying) return;

    await runBusyUiFlow(
      state: this,
      setBusy: () => setState(() => _isApplying = true),
      clearBusy: () => setState(() => _isApplying = false),
      run: () async {
        // 1) Commit IME into the controller.
        FocusScope.of(context).unfocus();
        // 2) Let focus loss + keyboard inset animate so [sizesManager.bodySize]
        // matches the main canvas before we compute layer offset/scale.
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;
        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;

        // 3) Sync text, rebuild layer with live editor geometry, then save.
        _watermarkText = _textController.text;
        if (mounted) setState(() {});
        _rebuildLayer();

        await WidgetsBinding.instance.endOfFrame;
        if (!mounted) return;

        await completeAndPop(state: this, context: context, onComplete: _notifyDone);
      },
    );
  }

  void _handleCancel() {
    if (_isApplying) return;
    _unfocusWatermarkField();
    _removeWorkingLayer();
    final editor = widget.editor;
    if (editor != null && _initialLayer != null) {
      editor.addLayer(
        _initialLayer!,
        blockSelectLayer: true,
        blockCaptureScreenshot: true,
        autoCorrectZoomOffset: false,
        autoCorrectZoomScale: false,
      );
    }
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: widget.theme,
      child: PopScope(
        canPop: false,
        onPopInvokedWithResult: (didPop, _) {
          if (!didPop) _handleCancel();
        },
        child: Scaffold(
          resizeToAvoidBottomInset: false,
          backgroundColor: widget.theme.scaffoldBackgroundColor,
          appBar: EditorActionAppBar(
            theme: widget.theme,
            showLeadingBack: true,
            onBack: _handleCancel,
            onUndo: () {},
            onRedo: () {},
            onConfirm: _handleApply,
            canUndo: false,
            canRedo: false,
            isBusy: _isApplying,
            showUndoRedo: false,
            confirmTooltip: _t('image_editor.apply', 'Apply'),
          ),
          body: Column(
            children: [
              Expanded(
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    IgnorePointer(
                      ignoring: _isApplying,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final maxPreview = Size(constraints.maxWidth, constraints.maxHeight);
                          final displayFit = fitSizeWithinBounds(widget.mainImageSize, maxPreview);
                          final previewBaseWidth = widget.editor?.configs.stickerEditor.initWidth ?? 100;
                          final previewCanvas = Size(
                            previewBaseWidth,
                            previewBaseWidth * (displayFit.height / displayFit.width),
                          );
                          final textScaler = MediaQuery.textScalerOf(context);

                          return Center(
                            child: SizedBox(
                              width: displayFit.width,
                              height: displayFit.height,
                              child: Stack(
                                fit: StackFit.expand,
                                children: [
                                  Positioned.fill(
                                    child: GestureDetector(
                                      behavior: HitTestBehavior.opaque,
                                      onTap: _unfocusWatermarkField,
                                      child: Image.memory(widget.imageBytes, fit: BoxFit.contain),
                                    ),
                                  ),
                                  Positioned.fill(
                                    child: IgnorePointer(
                                      child: FittedBox(
                                        fit: BoxFit.contain,
                                        alignment: Alignment.center,
                                        child: _buildWatermarkContentForSize(
                                          previewCanvas,
                                          textScaler: textScaler,
                                        ),
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
                    if (_isApplying)
                      Container(
                        color: Colors.black26,
                        child: const Center(child: CircularProgressIndicator()),
                      ),
                  ],
                ),
              ),
              IgnorePointer(ignoring: _isApplying, child: _buildControls()),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.black,
        child: SingleChildScrollView(
          padding: EdgeInsets.fromLTRB(12, 10, 12, 12 + bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildSelectorButtons(),
              const SizedBox(height: 10),
              _buildColorPicker(),
              const SizedBox(height: 10),
              if (_mode == WatermarkMode.text || _mode == WatermarkMode.both)
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _textController,
                        focusNode: _watermarkFocus,
                        decoration: InputDecoration(
                          labelText: _t('image_editor.watermark.text_label', 'Watermark text'),
                          labelStyle: TextStyle(color: Colors.white),
                          enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                          focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                        ),
                        style: const TextStyle(color: Colors.white),
                        onTapOutside: (_) => _unfocusWatermarkField(),
                        onEditingComplete: _unfocusWatermarkField,
                      ),
                    ),
                  ],
                ),
              if (_mode == WatermarkMode.logo || _mode == WatermarkMode.both)
                Row(
                  children: [
                    if (!kIsWeb)
                      IconButton(
                        tooltip: tooltipForPlatform(context, _t('image_editor.watermark.pick_logo', 'Pick logo')),
                        onPressed: _pickLogo,
                        icon: const Icon(Icons.image, color: Colors.white),
                      ),
                    if (_watermarkLogoBytes != null)
                      IconButton(
                        tooltip: tooltipForPlatform(
                          context,
                          _t('image_editor.watermark.remove_logo', 'Remove logo'),
                        ),
                        onPressed: _removeLogo,
                        icon: const Icon(Icons.delete_outline, color: Colors.white),
                      ),
                  ],
                ),
              const SizedBox(height: 10),
              Row(
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(
                      _t('image_editor.watermark.opacity', 'Opacity'),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: _opacity,
                      min: 0,
                      max: 1,
                      onChangeStart: (_) => _unfocusWatermarkField(),
                      onChanged: (v) {
                        setState(() => _opacity = v);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${(_opacity * 100).round()}%',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
              Row(
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(
                      _t('image_editor.watermark.angle', 'Angle'),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: _angleDegrees,
                      min: -180,
                      max: 180,
                      onChangeStart: (_) => _unfocusWatermarkField(),
                      onChanged: (v) {
                        setState(() => _angleDegrees = v);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text('${_angleDegrees.round()}°', style: const TextStyle(color: Colors.white, fontSize: 12)),
                  ),
                ],
              ),
              Row(
                children: [
                  SizedBox(
                    width: 62,
                    child: Text(
                      _t('image_editor.watermark.size', 'Size'),
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                  Expanded(
                    child: Slider(
                      value: _sizeFactor,
                      min: 0.5,
                      max: 2.0,
                      onChangeStart: (_) => _unfocusWatermarkField(),
                      onChanged: (v) {
                        setState(() => _sizeFactor = v);
                      },
                    ),
                  ),
                  SizedBox(
                    width: 60,
                    child: Text(
                      '${(_sizeFactor * 100).round()}%',
                      style: const TextStyle(color: Colors.white, fontSize: 12),
                    ),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  String _positionLabel(WatermarkPosition position) {
    switch (position) {
      case WatermarkPosition.topLeft:
        return _t('image_editor.watermark.position.top_left', 'Top Left');
      case WatermarkPosition.topRight:
        return _t('image_editor.watermark.position.top_right', 'Top Right');
      case WatermarkPosition.bottomLeft:
        return _t('image_editor.watermark.position.bottom_left', 'Bottom Left');
      case WatermarkPosition.bottomRight:
        return _t('image_editor.watermark.position.bottom_right', 'Bottom Right');
      case WatermarkPosition.center:
        return _t('image_editor.watermark.position.center', 'Center');
      case WatermarkPosition.patternGrid:
        return _t('image_editor.watermark.position.pattern_grid', 'Pattern Grid');
    }
  }

  String _modeLabel(WatermarkMode mode) {
    switch (mode) {
      case WatermarkMode.text:
        return _t('image_editor.watermark.mode.text', 'Text');
      case WatermarkMode.logo:
        return _t('image_editor.watermark.mode.logo', 'Logo');
      case WatermarkMode.both:
        return _t('image_editor.watermark.mode.text_logo', 'Text + Logo');
    }
  }

  Future<void> _openPositionPickerModal() async {
    _unfocusWatermarkField();
    final selected = await showModalBottomSheet<WatermarkPosition>(
      context: context,
      backgroundColor: const Color(0xFF1F1F1F),
      builder: (modalContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _t('image_editor.watermark.select_position', 'Select position'),
                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              for (final option in WatermarkPosition.values)
                ListTile(
                  leading: Icon(
                    option == _position ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: Colors.white,
                  ),
                  title: Text(_positionLabel(option), style: const TextStyle(color: Colors.white)),
                  onTap: () => Navigator.of(modalContext).pop(option),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null || selected == _position) return;
    setState(() => _position = selected);
  }

  Future<void> _openModePickerModal() async {
    _unfocusWatermarkField();
    final selected = await showModalBottomSheet<WatermarkMode>(
      context: context,
      backgroundColor: const Color(0xFF1F1F1F),
      builder: (modalContext) {
        final options = <WatermarkMode>[
          WatermarkMode.text,
          if (!kIsWeb) WatermarkMode.logo,
          if (!kIsWeb) WatermarkMode.both,
        ];
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    _t('image_editor.watermark.select_mode', 'Select mode'),
                    style: TextStyle(color: Colors.white70, fontSize: 12, fontWeight: FontWeight.w600),
                  ),
                ),
              ),
              for (final option in options)
                ListTile(
                  leading: Icon(
                    option == _mode ? Icons.radio_button_checked : Icons.radio_button_unchecked,
                    color: Colors.white,
                  ),
                  title: Text(_modeLabel(option), style: const TextStyle(color: Colors.white)),
                  onTap: () => Navigator.of(modalContext).pop(option),
                ),
              if (kIsWeb)
                Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    _t('image_editor.watermark.logo_modes_unavailable_web', 'Logo modes are unavailable on web'),
                    style: TextStyle(color: Colors.white54, fontSize: 11),
                  ),
                ),
            ],
          ),
        );
      },
    );

    if (!mounted || selected == null || selected == _mode) return;
    setState(() => _mode = selected);
  }

  Widget _buildSelectorButtons() {
    Widget button({required String label, required String value, required VoidCallback onTap}) {
      return Expanded(
        child: OutlinedButton(
          style: OutlinedButton.styleFrom(
            side: const BorderSide(color: Colors.white24),
            foregroundColor: Colors.white,
          ),
          onPressed: onTap,
          child: Text('$label: $value', overflow: TextOverflow.ellipsis),
        ),
      );
    }

    return Row(
      children: [
        button(
          label: _t('image_editor.watermark.position_label', 'Position'),
          value: _positionLabel(_position),
          onTap: _openPositionPickerModal,
        ),
        const SizedBox(width: 8),
        button(
          label: _t('image_editor.watermark.mode_label', 'Mode'),
          value: _modeLabel(_mode),
          onTap: _openModePickerModal,
        ),
      ],
    );
  }

  Widget _buildColorPicker() {
    return SizedBox(
      height: 34,
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (final color in _colorPresets)
              Padding(
                padding: const EdgeInsets.only(right: 10),
                child: GestureDetector(
                  onTap: () {
                    _unfocusWatermarkField();
                    setState(() => _textColorRgb = color);
                  },
                  child: Container(
                    width: 24,
                    height: 24,
                    decoration: BoxDecoration(
                      color: Color(0xFF000000 | color),
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: _textColorRgb == color ? Colors.white : Colors.white24,
                        width: _textColorRgb == color ? 2 : 1,
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
