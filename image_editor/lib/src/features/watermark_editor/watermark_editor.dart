import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_picker/image_picker.dart';
import 'package:pro_image_editor/pro_image_editor.dart';
import 'package:pro_image_editor/core/models/layers/layer_interaction.dart';

enum WatermarkMode { text, logo, both }

enum WatermarkPosition { topLeft, topRight, bottomLeft, bottomRight, center, patternGrid }

/// Watermark UI that previews and updates a live widget layer.
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
  static const List<int> _colorPresets = <int>[0xFFFFFF, 0x000000, 0xFACC15, 0x22C55E, 0x38BDF8, 0xA78BFA, 0xEF4444];

  WatermarkMode _mode = WatermarkMode.text;
  WatermarkPosition _position = WatermarkPosition.bottomRight;
  String _watermarkText = 'Your Name';
  Uint8List? _watermarkLogoBytes;
  int _textColorRgb = 0xFFFFFF;
  double _opacity = 0.5;
  double _sizeFactor = 1.0;
  double _angleDegrees = 0.0;

  WidgetLayer? _initialLayer;

  @override
  void initState() {
    super.initState();
    _textController.text = _watermarkText;
    if (kIsWeb && _mode != WatermarkMode.text) {
      _mode = WatermarkMode.text;
    }
    // Delay layer mutations until after the first frame to avoid
    // triggering editor setState while this route is still building.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final existing = _findCurrentWatermarkLayer();
      if (existing != null) {
        _initialLayer = existing;
        widget.editor?.removeLayer(existing, blockCaptureScreenshot: true);
      }
      _rebuildLayer();
    });
  }

  @override
  void dispose() {
    _textController.dispose();
    super.dispose();
  }

  Size _fitImageRect(Size bodySize) {
    final imgAspect = widget.mainImageSize.width / widget.mainImageSize.height;
    final bodyAspect = bodySize.width / bodySize.height;

    if (imgAspect > bodyAspect) {
      final width = bodySize.width;
      final height = width / imgAspect;
      return Size(width, height);
    } else {
      final height = bodySize.height;
      final width = height * imgAspect;
      return Size(width, height);
    }
  }

  Future<void> _pickLogo() async {
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
    _rebuildLayer();
  }

  void _removeLogo() {
    setState(() {
      _watermarkLogoBytes = null;
    });
    _rebuildLayer();
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

  Widget _buildWatermarkContentForSize(Size canvasSize) {
    final hasText = _mode != WatermarkMode.logo && _watermarkText.trim().isNotEmpty;
    final hasLogo = _mode != WatermarkMode.text && _watermarkLogoBytes != null;
    if (!hasText && !hasLogo) return const SizedBox.shrink();

    final longSide = canvasSize.longestSide;
    final textFont = longSide * (_mode == WatermarkMode.both ? 0.026 : 0.032) * _sizeFactor;
    final logoBox = longSide * (_mode == WatermarkMode.both ? 0.045 : 0.06) * _sizeFactor;
    final gap = longSide * 0.012 * _sizeFactor;

    Widget item;
    if (_mode == WatermarkMode.text || !hasLogo) {
      item = Text(
        _watermarkText,
        style: TextStyle(
          color: Color(0xFF000000 | _textColorRgb),
          fontWeight: FontWeight.w600,
          fontSize: textFont,
          height: 1,
        ),
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
            style: TextStyle(
              color: Color(0xFF000000 | _textColorRgb),
              fontWeight: FontWeight.w600,
              fontSize: textFont,
              height: 1,
            ),
          ),
        ],
      );
    }

    item = Opacity(
      opacity: _opacity.clamp(0.0, 1.0),
      child: Transform.rotate(angle: _angleDegrees * 3.141592653589793 / 180.0, child: item),
    );

    if (_position == WatermarkPosition.patternGrid) {
      final stepX = canvasSize.width * (_mode == WatermarkMode.both ? 0.28 : 0.22);
      final stepY = canvasSize.height * (_mode == WatermarkMode.both ? 0.20 : 0.16);
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
      child: Align(alignment: alignment, child: item),
    );
  }

  void _removeWorkingLayer() {
    final current = _findCurrentWatermarkLayer();
    if (current != null) {
      widget.editor?.removeLayer(current, blockCaptureScreenshot: true);
    }
  }

  void _rebuildLayer() {
    final editor = widget.editor;
    _removeWorkingLayer();
    if (editor == null || !_hasRenderableContent) return;

    final fit = _fitImageRect(widget.mainBodySize);
    final initWidth = editor.configs.stickerEditor.initWidth;
    final layerCanvas = Size(initWidth, initWidth * (fit.height / fit.width));
    final topLeft = Offset((widget.mainBodySize.width - fit.width) / 2, (widget.mainBodySize.height - fit.height) / 2);
    final fractional = editor.configs.stickerEditor.layerFractionalOffset;
    final desiredOffsetInBody = Offset(topLeft.dx - fractional.dx * fit.width, topLeft.dy - fractional.dy * fit.height);
    final offset = Offset(
      desiredOffsetInBody.dx - widget.mainBodySize.width / 2,
      desiredOffsetInBody.dy - widget.mainBodySize.height / 2,
    );
    final scale = fit.width / initWidth;
    final layer = WidgetLayer(
      widget: _buildWatermarkContentForSize(layerCanvas),
      offset: offset,
      scale: scale,
      interaction: LayerInteraction.fromDefaultValue(false),
      groupId: _watermarkGroupId,
      meta: const {'type': 'watermark'},
    );
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
    await _notifyDone();
    if (mounted && Navigator.of(context).canPop()) {
      Navigator.of(context).pop();
    }
  }

  void _handleCancel() {
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
          backgroundColor: widget.theme.scaffoldBackgroundColor,
          appBar: AppBar(
            automaticallyImplyLeading: false,
            backgroundColor: widget.theme.appBarTheme.backgroundColor ?? Colors.black,
            foregroundColor: widget.theme.appBarTheme.foregroundColor ?? Colors.white,
            leading: IconButton(tooltip: 'Back', icon: const Icon(Icons.arrow_back), onPressed: _handleCancel),
            actions: [
              IconButton(
                tooltip: 'Apply',
                icon: const Icon(Icons.check, size: 28, color: Colors.white),
                onPressed: _handleApply,
              ),
            ],
          ),
          body: LayoutBuilder(
            builder: (context, _) {
              final fitted = _fitImageRect(widget.mainBodySize);
              final previewBaseWidth = widget.editor?.configs.stickerEditor.initWidth ?? 100;
              final previewCanvas = Size(previewBaseWidth, previewBaseWidth * (fitted.height / fitted.width));

              return Column(
                children: [
                  Expanded(
                    child: Center(
                      child: SizedBox(
                        width: fitted.width,
                        height: fitted.height,
                        child: Stack(
                          fit: StackFit.expand,
                          children: [
                            Image.memory(widget.imageBytes, fit: BoxFit.fill),
                            IgnorePointer(
                              child: SizedBox(
                                width: fitted.width,
                                child: FittedBox(
                                  fit: BoxFit.contain,
                                  child: _buildWatermarkContentForSize(previewCanvas),
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  _buildControls(),
                ],
              );
            },
          ),
        ),
      ),
    );
  }

  Widget _buildControls() {
    return SafeArea(
      top: false,
      child: Container(
        color: Colors.black,
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 12),
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
                      decoration: const InputDecoration(
                        labelText: 'Watermark text',
                        labelStyle: TextStyle(color: Colors.white),
                        enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: Colors.white)),
                      ),
                      style: const TextStyle(color: Colors.white),
                      onChanged: (v) {
                        setState(() => _watermarkText = v);
                        _rebuildLayer();
                      },
                    ),
                  ),
                ],
              ),
            if (_mode == WatermarkMode.logo || _mode == WatermarkMode.both)
              Row(
                children: [
                  if (!kIsWeb)
                    IconButton(
                      tooltip: 'Pick logo',
                      onPressed: _pickLogo,
                      icon: const Icon(Icons.image, color: Colors.white),
                    ),
                  if (_watermarkLogoBytes != null)
                    IconButton(
                      tooltip: 'Remove logo',
                      onPressed: _removeLogo,
                      icon: const Icon(Icons.delete_outline, color: Colors.white),
                    ),
                ],
              ),
            const SizedBox(height: 10),
            Row(
              children: [
                const SizedBox(
                  width: 62,
                  child: Text('Opacity', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
                Expanded(
                  child: Slider(
                    value: _opacity,
                    min: 0,
                    max: 1,
                    onChanged: (v) {
                      setState(() => _opacity = v);
                      _rebuildLayer();
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
                const SizedBox(
                  width: 62,
                  child: Text('Angle', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
                Expanded(
                  child: Slider(
                    value: _angleDegrees,
                    min: -180,
                    max: 180,
                    onChanged: (v) {
                      setState(() => _angleDegrees = v);
                      _rebuildLayer();
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
                const SizedBox(
                  width: 62,
                  child: Text('Size', style: TextStyle(color: Colors.white, fontSize: 12)),
                ),
                Expanded(
                  child: Slider(
                    value: _sizeFactor,
                    min: 0.5,
                    max: 2.0,
                    onChanged: (v) {
                      setState(() => _sizeFactor = v);
                      _rebuildLayer();
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
    );
  }

  String _positionLabel(WatermarkPosition position) {
    switch (position) {
      case WatermarkPosition.topLeft:
        return 'Top Left';
      case WatermarkPosition.topRight:
        return 'Top Right';
      case WatermarkPosition.bottomLeft:
        return 'Bottom Left';
      case WatermarkPosition.bottomRight:
        return 'Bottom Right';
      case WatermarkPosition.center:
        return 'Center';
      case WatermarkPosition.patternGrid:
        return 'Pattern Grid';
    }
  }

  String _modeLabel(WatermarkMode mode) {
    switch (mode) {
      case WatermarkMode.text:
        return 'Text';
      case WatermarkMode.logo:
        return 'Logo';
      case WatermarkMode.both:
        return 'Text + Logo';
    }
  }

  Future<void> _openPositionPickerModal() async {
    final selected = await showModalBottomSheet<WatermarkPosition>(
      context: context,
      backgroundColor: const Color(0xFF1F1F1F),
      builder: (modalContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select position',
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
    _rebuildLayer();
  }

  Future<void> _openModePickerModal() async {
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
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 12, 16, 4),
                child: Align(
                  alignment: Alignment.centerLeft,
                  child: Text(
                    'Select mode',
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
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                  child: Text(
                    'Logo modes are unavailable on web',
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
    _rebuildLayer();
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
        button(label: 'Position', value: _positionLabel(_position), onTap: _openPositionPickerModal),
        const SizedBox(width: 8),
        button(label: 'Mode', value: _modeLabel(_mode), onTap: _openModePickerModal),
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
                    setState(() => _textColorRgb = color);
                    _rebuildLayer();
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
