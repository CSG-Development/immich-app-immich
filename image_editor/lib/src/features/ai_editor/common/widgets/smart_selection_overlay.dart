import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/brush_strokes.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/layout_utils.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/ai_modal_ui.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/mask_editor_appbar.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/mask_selection_widgets.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/mask_with_strokes_overlay.dart';
import 'package:image_editor/src/features/services/image_worker.dart';
import 'package:pro_image_editor/shared/widgets/flat_icon_text_button.dart';

enum SmartSelectionShape { rectangle, ellipse, lasso }

enum SmartSelectionTool { brush, eraser }
enum SmartSelectionBottomAction { stars, target, brush, eraser }

class SmartSelectionOverlay extends StatefulWidget {
  const SmartSelectionOverlay({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.backgroundRemovalService,
    required this.onApplyMask,
    required this.onCancel,
    this.title,
    this.ensureModelReady,
    this.failureMessage = 'Failed to detect subject',
    this.applyDilatePercent = 0.02,
    this.segmentationThreshold = 0.5,
    this.softSegmentationMask = false,
    this.segmentationFeatherRadius = 0,
  });

  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final BackgroundRemovalService backgroundRemovalService;
  final Future<void> Function(img.Image mask) onApplyMask;
  final VoidCallback onCancel;
  final String? title;
  final Future<bool> Function()? ensureModelReady;
  final String failureMessage;
  final double applyDilatePercent;
  final double segmentationThreshold;
  final bool softSegmentationMask;
  final int segmentationFeatherRadius;

  @override
  State<SmartSelectionOverlay> createState() => _SmartSelectionOverlayState();
}

class _SmartSelectionOverlayState extends State<SmartSelectionOverlay> {
  final StrokeHistory _strokeHistory = StrokeHistory();
  img.Image? _initialMask;
  final List<img.Image?> _baseMaskHistory = [null];
  int _baseMaskHistoryIndex = 0;
  BrushStroke? _lastStrokeForCurrentDrag;

  static const double _minBrushRadius = 6.0;
  static const double _maxBrushRadius = 48.0;
  static const double _minTargetSizeDisplayPx = 12.0;
  double _brushRadius = 24.0;
  bool _isDetecting = false;

  SmartSelectionTool _selectedTool = SmartSelectionTool.brush;
  SmartSelectionBottomAction _activeBottomAction =
      SmartSelectionBottomAction.brush;
  SmartSelectionShape? _targetShape;
  Offset? _rectStart;
  Offset? _rectCurrent;
  final List<Offset> _lassoPoints = [];

  bool get _isTargetMode => _targetShape != null;
  bool get _showBrushSlider =>
      !_isTargetMode &&
      (_selectedTool == SmartSelectionTool.brush ||
          _selectedTool == SmartSelectionTool.eraser);
  bool get _canUndo => _strokeHistory.canUndo || _baseMaskHistoryIndex > 0;
  bool get _canRedo =>
      _baseMaskHistoryIndex < _baseMaskHistory.length - 1 ||
      _strokeHistory.canRedo;

  void _pushBaseMaskHistory(img.Image? mask) {
    if (_baseMaskHistoryIndex < _baseMaskHistory.length - 1) {
      _baseMaskHistory.removeRange(
        _baseMaskHistoryIndex + 1,
        _baseMaskHistory.length,
      );
    }
    _baseMaskHistory.add(mask);
    _baseMaskHistoryIndex = _baseMaskHistory.length - 1;
  }

  void _undo() {
    if (!_canUndo) return;
    setState(() {
      if (_strokeHistory.canUndo) {
        _strokeHistory.undo();
        return;
      }
      if (_baseMaskHistoryIndex > 0) {
        _baseMaskHistoryIndex--;
        _initialMask = _baseMaskHistory[_baseMaskHistoryIndex];
      }
    });
  }

  void _redo() {
    if (!_canRedo) return;
    setState(() {
      if (_baseMaskHistoryIndex < _baseMaskHistory.length - 1) {
        _baseMaskHistoryIndex++;
        _initialMask = _baseMaskHistory[_baseMaskHistoryIndex];
        return;
      }
      _strokeHistory.redo();
    });
  }

  Future<void> _apply() async {
    Map<String, Object>? baseMask;
    final initialMask = _initialMask;
    if (initialMask != null) {
      final baseData = Uint8List(initialMask.width * initialMask.height);
      var baseIdx = 0;
      for (var y = 0; y < initialMask.height; y++) {
        for (var x = 0; x < initialMask.width; x++) {
          final p = initialMask.getPixel(x, y);
          baseData[baseIdx++] = p.r.toInt().clamp(0, 255);
        }
      }
      baseMask = <String, Object>{
        'width': initialMask.width,
        'height': initialMask.height,
        'data': baseData,
      };
    }

    final maskData = await ImageWorker.instance.buildStrokeMask(
      width: widget.imageWidth,
      height: widget.imageHeight,
      strokes: _strokeHistory.strokes
          .map(
            (s) => <String, Object>{
              'x': s.x,
              'y': s.y,
              'radius': s.radius,
              'isAdd': s.isAdd,
            },
          )
          .toList(),
      baseMask: baseMask,
      dilatePercent: widget.applyDilatePercent,
    );
    if (maskData == null) return;

    final width = maskData['width'] as int;
    final height = maskData['height'] as int;
    final data = maskData['data'] as Uint8List;
    if (data.length != width * height) return;

    final mask = img.Image(width: width, height: height);
    var idx = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final v = data[idx++];
        mask.setPixel(x, y, img.ColorRgb8(v, v, v));
      }
    }
    await widget.onApplyMask(mask);
  }

  Offset _clampToDisplay(Offset p, Size size) => Offset(
    p.dx.clamp(0.0, size.width),
    p.dy.clamp(0.0, size.height),
  );

  Rect? _currentRect() {
    final a = _rectStart;
    final b = _rectCurrent;
    if (a == null || b == null) return null;
    return Rect.fromPoints(a, b);
  }

  Rect? _lassoBounds() {
    if (_lassoPoints.isEmpty) return null;
    var minX = _lassoPoints.first.dx;
    var minY = _lassoPoints.first.dy;
    var maxX = _lassoPoints.first.dx;
    var maxY = _lassoPoints.first.dy;
    for (final p in _lassoPoints) {
      if (p.dx < minX) minX = p.dx;
      if (p.dx > maxX) maxX = p.dx;
      if (p.dy < minY) minY = p.dy;
      if (p.dy > maxY) maxY = p.dy;
    }
    return Rect.fromLTRB(minX, minY, maxX, maxY);
  }

  Rect? _currentTargetRect() {
    if (_targetShape == SmartSelectionShape.lasso) {
      return _lassoBounds();
    }
    return _currentRect();
  }

  Future<bool> _ensureModelReady() async {
    final ensureModelReady = widget.ensureModelReady;
    if (ensureModelReady == null) return true;
    return ensureModelReady();
  }

  Future<void> _runFullSmartSelection() async {
    if (_isDetecting) return;
    setState(() {
      _targetShape = null;
      _activeBottomAction = SmartSelectionBottomAction.stars;
    });
    final modelOk = await _ensureModelReady();
    if (!modelOk || !mounted) return;
    setState(() => _isDetecting = true);
    try {
      final mask = await widget.backgroundRemovalService.getSegmentationMask(
        widget.imageBytes,
        threshold: widget.segmentationThreshold,
        softMask: widget.softSegmentationMask,
        featherRadius: widget.segmentationFeatherRadius,
      );
      if (!mounted) return;
      if (mask == null) {
        _showFailure();
        return;
      }
      final mergedMask = _mergeMaskWithCurrent(mask);
      setState(() {
        _initialMask = mergedMask;
        _pushBaseMaskHistory(mergedMask);
      });
    } catch (_) {
      if (!mounted) return;
      _showFailure();
    } finally {
      if (mounted) {
        setState(() => _isDetecting = false);
      }
    }
  }

  Future<void> _openShapePicker() async {
    if (_isDetecting) return;
    final shape = await showModalBottomSheet<SmartSelectionShape>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('Select target shape', style: AiModalUi.sectionTitleStyle),
                const SizedBox(height: AiModalUi.itemSpacing),
                Row(
                  children: [
                    Expanded(
                      child: AiModalSelectTile(
                        icon: Icons.crop_free,
                        label: 'Rectangle',
                        isSelected: false,
                        onTap: () => Navigator.of(ctx).pop(SmartSelectionShape.rectangle),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AiModalSelectTile(
                        icon: Icons.circle_outlined,
                        label: 'Ellipse',
                        isSelected: false,
                        onTap: () => Navigator.of(ctx).pop(SmartSelectionShape.ellipse),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: AiModalSelectTile(
                        icon: Icons.gesture,
                        label: 'Lasso',
                        isSelected: false,
                        onTap: () => Navigator.of(ctx).pop(SmartSelectionShape.lasso),
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
    if (shape == null || !mounted) return;
    setState(() {
      _targetShape = shape;
      _activeBottomAction = SmartSelectionBottomAction.target;
      _rectStart = null;
      _rectCurrent = null;
      _lassoPoints.clear();
    });
  }

  void _showFailure() {
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(SnackBar(content: Text(widget.failureMessage)));
  }

  img.Image _mergeMaskWithCurrent(img.Image incomingMask) {
    final current = _initialMask;
    if (current == null) {
      return incomingMask;
    }
    if (current.width != incomingMask.width ||
        current.height != incomingMask.height) {
      return incomingMask;
    }
    final merged = img.Image(
      width: incomingMask.width,
      height: incomingMask.height,
    );
    for (var y = 0; y < incomingMask.height; y++) {
      for (var x = 0; x < incomingMask.width; x++) {
        final currentV = current.getPixel(x, y).r.toInt().clamp(0, 255);
        final incomingV = incomingMask.getPixel(x, y).r.toInt().clamp(0, 255);
        final mergedV = math.max(currentV, incomingV);
        merged.setPixel(x, y, img.ColorRgb8(mergedV, mergedV, mergedV));
      }
    }
    return merged;
  }

  void _onPanStart(Offset localPosition, Size displaySize) {
    if (_isTargetMode) {
      setState(() {
        final clamped = _clampToDisplay(localPosition, displaySize);
        if (_targetShape == SmartSelectionShape.lasso) {
          _lassoPoints
            ..clear()
            ..add(clamped);
        } else {
          _rectStart = clamped;
          _rectCurrent = clamped;
        }
      });
      return;
    }
    setState(() {
      _strokeHistory.startBatch(_selectedTool == SmartSelectionTool.brush);
      _lastStrokeForCurrentDrag = null;
      _addStrokePoint(localPosition, displaySize);
    });
  }

  void _onPanUpdate(Offset localPosition, Size displaySize) {
    if (_isTargetMode) {
      setState(() {
        final clamped = _clampToDisplay(localPosition, displaySize);
        if (_targetShape == SmartSelectionShape.lasso) {
          _lassoPoints.add(clamped);
        } else {
          _rectCurrent = clamped;
        }
      });
      return;
    }
    setState(() {
      _addStrokePoint(localPosition, displaySize);
    });
  }

  Future<void> _onPanEnd(Size displaySize) async {
    if (!_isTargetMode) return;
    final targetRect = _currentTargetRect();
    if (targetRect == null) return;
    if (targetRect.width < _minTargetSizeDisplayPx ||
        targetRect.height < _minTargetSizeDisplayPx) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Selection is too small. Draw a larger target.'),
          ),
        );
      }
      setState(() {
        _rectStart = null;
        _rectCurrent = null;
        _lassoPoints.clear();
      });
      return;
    }
    if (_targetShape == SmartSelectionShape.lasso && _lassoPoints.length < 3) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Lasso needs at least 3 points.')),
        );
      }
      setState(() {
        _lassoPoints.clear();
      });
      return;
    }
    await _runSmartSelectionForTarget(displaySize: displaySize);
  }

  void _addStrokePoint(Offset localPosition, Size displaySize) {
    final stroke = createStrokeFromLocalPosition(
      localPosition: localPosition,
      displaySize: displaySize,
      imageWidth: widget.imageWidth,
      imageHeight: widget.imageHeight,
      brushRadius: _brushRadius,
    );
    final last = _lastStrokeForCurrentDrag;
    if (last != null) {
      final dx = stroke.x - last.x;
      final dy = stroke.y - last.y;
      final distance = math.sqrt(dx * dx + dy * dy);
      final step = stroke.radius * 0.6;
      final steps = step > 0 ? (distance / step).ceil() : 0;
      for (var i = 1; i <= steps; i++) {
        final t = i / (steps + 1);
        _strokeHistory.addStroke(last.x + dx * t, last.y + dy * t, stroke.radius);
      }
    }
    _strokeHistory.addStroke(stroke.x, stroke.y, stroke.radius);
    _lastStrokeForCurrentDrag = stroke;
  }

  Future<void> _runSmartSelectionForTarget({required Size displaySize}) async {
    if (_isDetecting || _targetShape == null) return;
    final modelOk = await _ensureModelReady();
    if (!modelOk || !mounted) return;
    setState(() => _isDetecting = true);
    try {
      final mask = await _detectMaskInTarget(displaySize: displaySize);
      if (!mounted) return;
      if (mask == null) {
        _showFailure();
        return;
      }
      final mergedMask = _mergeMaskWithCurrent(mask);
      setState(() {
        _initialMask = mergedMask;
        _pushBaseMaskHistory(mergedMask);
        _targetShape = null;
        _activeBottomAction = SmartSelectionBottomAction.brush;
        _selectedTool = SmartSelectionTool.brush;
        _rectStart = null;
        _rectCurrent = null;
        _lassoPoints.clear();
      });
    } catch (_) {
      if (!mounted) return;
      _showFailure();
    } finally {
      if (mounted) {
        setState(() => _isDetecting = false);
      }
    }
  }

  Future<img.Image?> _detectMaskInTarget({required Size displaySize}) async {
    final shape = _targetShape;
    if (shape == null) return null;
    final source = img.decodeImage(widget.imageBytes);
    if (source == null) return null;

    final displayRect = _currentTargetRect();
    if (displayRect == null) return null;

    final sx = widget.imageWidth / displaySize.width;
    final sy = widget.imageHeight / displaySize.height;
    final left = (displayRect.left * sx).floor().clamp(0, widget.imageWidth - 1);
    final top = (displayRect.top * sy).floor().clamp(0, widget.imageHeight - 1);
    final right = (displayRect.right * sx).ceil().clamp(1, widget.imageWidth);
    final bottom = (displayRect.bottom * sy).ceil().clamp(1, widget.imageHeight);
    final roiWidth = math.max(1, right - left);
    final roiHeight = math.max(1, bottom - top);

    final cropped = img.copyCrop(
      source,
      x: left,
      y: top,
      width: roiWidth,
      height: roiHeight,
    );
    final croppedBytes = Uint8List.fromList(img.encodePng(cropped));
    final roiMask = await widget.backgroundRemovalService.getSegmentationMask(
      croppedBytes,
      threshold: widget.segmentationThreshold,
      softMask: widget.softSegmentationMask,
      featherRadius: widget.segmentationFeatherRadius,
    );
    if (roiMask == null) return null;

    final fullMask = img.Image(width: widget.imageWidth, height: widget.imageHeight);
    final lassoInRoi = _targetShape == SmartSelectionShape.lasso
        ? _lassoPoints
            .map((p) => Offset((p.dx * sx) - left, (p.dy * sy) - top))
            .toList()
        : const <Offset>[];

    for (var y = 0; y < roiMask.height; y++) {
      final targetY = top + y;
      if (targetY < 0 || targetY >= fullMask.height) continue;
      for (var x = 0; x < roiMask.width; x++) {
        final targetX = left + x;
        if (targetX < 0 || targetX >= fullMask.width) continue;
        if (!_pointInsideShape(shape, x, y, roiMask.width, roiMask.height, lassoInRoi)) {
          continue;
        }
        final p = roiMask.getPixel(x, y);
        final v = p.r.toInt().clamp(0, 255);
        fullMask.setPixel(targetX, targetY, img.ColorRgb8(v, v, v));
      }
    }

    return fullMask;
  }

  bool _pointInsideShape(
    SmartSelectionShape shape,
    int x,
    int y,
    int width,
    int height,
    List<Offset> lassoInRoi,
  ) {
    if (shape == SmartSelectionShape.rectangle) return true;
    if (shape == SmartSelectionShape.ellipse) {
      final rx = width / 2.0;
      final ry = height / 2.0;
      if (rx <= 0 || ry <= 0) return false;
      final cx = rx;
      final cy = ry;
      final nx = (x + 0.5 - cx) / rx;
      final ny = (y + 0.5 - cy) / ry;
      return (nx * nx + ny * ny) <= 1.0;
    }
    return _pointInPolygon(Offset(x + 0.5, y + 0.5), lassoInRoi);
  }

  bool _pointInPolygon(Offset p, List<Offset> polygon) {
    if (polygon.length < 3) return false;
    var inside = false;
    var j = polygon.length - 1;
    for (var i = 0; i < polygon.length; i++) {
      final xi = polygon[i].dx;
      final yi = polygon[i].dy;
      final xj = polygon[j].dx;
      final yj = polygon[j].dy;
      final intersects =
          ((yi > p.dy) != (yj > p.dy)) &&
          (p.dx < ((xj - xi) * (p.dy - yi)) / ((yj - yi) + 1e-9) + xi);
      if (intersects) inside = !inside;
      j = i;
    }
    return inside;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: MaskEditorAppBar(
        onCancel: widget.onCancel,
        onApply: _apply,
        applyEnabled: _initialMask != null || _strokeHistory.strokes.isNotEmpty,
        canUndo: _canUndo,
        canRedo: _canRedo,
        onUndo: _undo,
        onRedo: _redo,
        title: widget.title,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final displaySize = fitSizeWithinBounds(
                    Size(widget.imageWidth.toDouble(), widget.imageHeight.toDouble()),
                    Size(constraints.maxWidth, constraints.maxHeight),
                  );
                  final rect = _currentRect();

                  return Stack(
                    children: [
                      Center(
                        child: GestureDetector(
                          onPanStart: (d) => _onPanStart(d.localPosition, displaySize),
                          onPanUpdate: (d) => _onPanUpdate(d.localPosition, displaySize),
                          onPanEnd: (_) => _onPanEnd(displaySize),
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              SizedBox(
                                width: displaySize.width,
                                height: displaySize.height,
                                child: Image.memory(widget.imageBytes, fit: BoxFit.cover),
                              ),
                              Positioned(
                                left: 0,
                                top: 0,
                                child: MaskWithStrokesOverlay(
                                  mask: _initialMask,
                                  strokes: _strokeHistory.strokes,
                                  displayWidth: displaySize.width,
                                  displayHeight: displaySize.height,
                                  imageWidth: widget.imageWidth.toDouble(),
                                  imageHeight: widget.imageHeight.toDouble(),
                                ),
                              ),
                              if (_isTargetMode)
                                Positioned.fill(
                                  child: IgnorePointer(
                                    child: CustomPaint(
                                      painter: TargetShapePainter(
                                        shapeName: _targetShape?.name,
                                        rect: rect,
                                        lassoPoints: _lassoPoints,
                                      ),
                                    ),
                                  ),
                                ),
                              if (_isDetecting)
                                const Positioned.fill(
                                  child: ColoredBox(
                                    color: Colors.black38,
                                    child: Center(child: CircularProgressIndicator()),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      if (_showBrushSlider)
                        Positioned(
                          top: 12,
                          right: 12,
                          child: VerticalBrushSlider(
                            value: _brushRadius,
                            min: _minBrushRadius,
                            max: _maxBrushRadius,
                            onChanged: (v) {
                              setState(() {
                                _brushRadius = v;
                              });
                            },
                          ),
                        ),
                    ],
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  _buildBottomActionButton(
                    label: 'Smart',
                    icon: Icons.auto_awesome,
                    isActive: _activeBottomAction == SmartSelectionBottomAction.stars,
                    onPressed: _isDetecting ? null : _runFullSmartSelection,
                  ),
                  _buildBottomActionButton(
                    label: 'Target',
                    icon: Icons.gesture,
                    isActive: _activeBottomAction == SmartSelectionBottomAction.target,
                    onPressed: _isDetecting ? null : _openShapePicker,
                  ),
                  _buildBottomActionButton(
                    label: 'Brush',
                    icon: Icons.brush,
                    isActive: _activeBottomAction == SmartSelectionBottomAction.brush,
                    onPressed: _isDetecting
                        ? null
                        : () {
                            setState(() {
                              _targetShape = null;
                              _selectedTool = SmartSelectionTool.brush;
                              _activeBottomAction = SmartSelectionBottomAction.brush;
                            });
                          },
                  ),
                  _buildBottomActionButton(
                    label: 'Eraser',
                    icon: Icons.auto_fix_off,
                    isActive: _activeBottomAction == SmartSelectionBottomAction.eraser,
                    onPressed: _isDetecting
                        ? null
                        : () {
                            setState(() {
                              _targetShape = null;
                              _selectedTool = SmartSelectionTool.eraser;
                              _activeBottomAction = SmartSelectionBottomAction.eraser;
                            });
                          },
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBottomActionButton({
    required String label,
    required IconData icon,
    required bool isActive,
    required VoidCallback? onPressed,
  }) {
    final color = isActive ? Colors.white : Colors.white70;
    return FlatIconTextButton(
      label: Text(label, style: TextStyle(fontSize: 10.0, color: color)),
      icon: Icon(icon, size: 22, color: color),
      onPressed: onPressed,
    );
  }
}

