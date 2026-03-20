import 'dart:typed_data';
import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/brush_strokes.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/layout_utils.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/mask_utils.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/mask_editor_appbar.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/mask_selection_widgets.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/mask_with_strokes_overlay.dart';
import 'package:pro_image_editor/shared/widgets/flat_icon_text_button.dart';

typedef SmartInsertionResult = ({Uint8List cutoutBytes, img.Image placementMask});

enum SmartInsertionShape { rectangle, ellipse, lasso }

enum SmartInsertionTool { brush, eraser }

enum SmartInsertionBottomAction { target, brush, eraser }

class SmartInsertionOverlay extends StatefulWidget {
  const SmartInsertionOverlay({
    super.key,
    required this.baseImageBytes,
    required this.baseImageWidth,
    required this.baseImageHeight,
    required this.cutoutBytes,
    required this.onApply,
    required this.onCancel,
  });

  final Uint8List baseImageBytes;
  final int baseImageWidth;
  final int baseImageHeight;
  final Uint8List cutoutBytes;
  final Future<void> Function(SmartInsertionResult result) onApply;
  final VoidCallback onCancel;

  @override
  State<SmartInsertionOverlay> createState() => _SmartInsertionOverlayState();
}

class _SmartInsertionOverlayState extends State<SmartInsertionOverlay> {
  final StrokeHistory _strokeHistory = StrokeHistory();
  img.Image? _initialMask;
  final List<img.Image?> _baseMaskHistory = [null];
  int _baseMaskHistoryIndex = 0;
  BrushStroke? _lastStrokeForCurrentDrag;

  static const double _minBrushRadius = 6.0;
  static const double _maxBrushRadius = 48.0;
  static const double _minTargetSizeDisplayPx = 12.0;
  double _brushRadius = 24.0;
  SmartInsertionTool _selectedTool = SmartInsertionTool.brush;
  SmartInsertionBottomAction _activeBottomAction = SmartInsertionBottomAction.brush;
  SmartInsertionShape? _targetShape;
  Offset? _rectStart;
  Offset? _rectCurrent;
  final List<Offset> _lassoPoints = [];
  bool _isApplying = false;

  bool get _isTargetMode => _targetShape != null;
  bool get _showBrushSlider => !_isTargetMode;
  bool get _canUndo => _strokeHistory.canUndo || _baseMaskHistoryIndex > 0;
  bool get _canRedo => _baseMaskHistoryIndex < _baseMaskHistory.length - 1 || _strokeHistory.canRedo;

  void _pushBaseMaskHistory(img.Image? mask) {
    if (_baseMaskHistoryIndex < _baseMaskHistory.length - 1) {
      _baseMaskHistory.removeRange(_baseMaskHistoryIndex + 1, _baseMaskHistory.length);
    }
    _baseMaskHistory.add(mask);
    _baseMaskHistoryIndex = _baseMaskHistory.length - 1;
  }

  Offset _clampToDisplay(Offset p, Size size) => Offset(p.dx.clamp(0.0, size.width), p.dy.clamp(0.0, size.height));

  void _onPanStart(Offset localPosition, Size displaySize) {
    if (_isTargetMode) {
      setState(() {
        final clamped = _clampToDisplay(localPosition, displaySize);
        if (_targetShape == SmartInsertionShape.lasso) {
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
    _strokeHistory.startBatch(_selectedTool == SmartInsertionTool.brush);
    _lastStrokeForCurrentDrag = null;
    _addStrokePoint(localPosition, displaySize);
    setState(() {});
  }

  void _onPanUpdate(Offset localPosition, Size displaySize) {
    if (_isTargetMode) {
      setState(() {
        final clamped = _clampToDisplay(localPosition, displaySize);
        if (_targetShape == SmartInsertionShape.lasso) {
          _lassoPoints.add(clamped);
        } else {
          _rectCurrent = clamped;
        }
      });
      return;
    }
    _addStrokePoint(localPosition, displaySize);
    setState(() {});
  }

  void _onPanEnd(Size displaySize) {
    if (!_isTargetMode) {
      _lastStrokeForCurrentDrag = null;
      return;
    }
    final targetRect = _currentTargetRect();
    if (targetRect == null) return;
    if (targetRect.width < _minTargetSizeDisplayPx || targetRect.height < _minTargetSizeDisplayPx) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Selection is too small. Draw a larger target.')));
      setState(() {
        _rectStart = null;
        _rectCurrent = null;
        _lassoPoints.clear();
      });
      return;
    }
    if (_targetShape == SmartInsertionShape.lasso && _lassoPoints.length < 3) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Lasso needs at least 3 points.')));
      setState(() => _lassoPoints.clear());
      return;
    }
    _applyTargetShapeToMask(displaySize: displaySize);
  }

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
    if (_targetShape == SmartInsertionShape.lasso) {
      return _lassoBounds();
    }
    return _currentRect();
  }

  void _addStrokePoint(Offset localPosition, Size displaySize) {
    final stroke = createStrokeFromLocalPosition(
      localPosition: localPosition,
      displaySize: displaySize,
      imageWidth: widget.baseImageWidth,
      imageHeight: widget.baseImageHeight,
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

  void _openShapePicker() async {
    final shape = await showModalBottomSheet<SmartInsertionShape>(
      context: context,
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              ListTile(
                leading: const Icon(Icons.crop_free),
                title: const Text('Rectangle'),
                onTap: () => Navigator.of(ctx).pop(SmartInsertionShape.rectangle),
              ),
              ListTile(
                leading: const Icon(Icons.circle_outlined),
                title: const Text('Ellipse'),
                onTap: () => Navigator.of(ctx).pop(SmartInsertionShape.ellipse),
              ),
              ListTile(
                leading: const Icon(Icons.gesture),
                title: const Text('Lasso'),
                onTap: () => Navigator.of(ctx).pop(SmartInsertionShape.lasso),
              ),
            ],
          ),
        );
      },
    );
    if (shape == null || !mounted) return;
    setState(() {
      _targetShape = shape;
      _activeBottomAction = SmartInsertionBottomAction.target;
      _rectStart = null;
      _rectCurrent = null;
      _lassoPoints.clear();
    });
  }

  void _applyTargetShapeToMask({required Size displaySize}) {
    final shapeMask = _rasterizeCurrentShapeMask(displaySize: displaySize);
    if (shapeMask == null) return;
    final merged = _mergeMaskWithCurrent(shapeMask);
    setState(() {
      _initialMask = merged;
      _pushBaseMaskHistory(merged);
      _targetShape = null;
      _activeBottomAction = SmartInsertionBottomAction.brush;
      _selectedTool = SmartInsertionTool.brush;
      _rectStart = null;
      _rectCurrent = null;
      _lassoPoints.clear();
    });
  }

  img.Image _mergeMaskWithCurrent(img.Image incomingMask) {
    final current = _initialMask;
    if (current == null) return incomingMask;
    if (current.width != incomingMask.width || current.height != incomingMask.height) {
      return incomingMask;
    }
    final merged = img.Image(width: incomingMask.width, height: incomingMask.height);
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

  img.Image? _rasterizeCurrentShapeMask({required Size displaySize}) {
    final shape = _targetShape;
    if (shape == null) return null;
    final displayRect = _currentTargetRect();
    if (displayRect == null) return null;

    final sx = widget.baseImageWidth / displaySize.width;
    final sy = widget.baseImageHeight / displaySize.height;
    final left = (displayRect.left * sx).floor().clamp(0, widget.baseImageWidth - 1);
    final top = (displayRect.top * sy).floor().clamp(0, widget.baseImageHeight - 1);
    final right = (displayRect.right * sx).ceil().clamp(1, widget.baseImageWidth);
    final bottom = (displayRect.bottom * sy).ceil().clamp(1, widget.baseImageHeight);
    final roiWidth = math.max(1, right - left);
    final roiHeight = math.max(1, bottom - top);

    final shapeMask = img.Image(width: widget.baseImageWidth, height: widget.baseImageHeight);
    final lassoInRoi = shape == SmartInsertionShape.lasso
        ? _lassoPoints.map((p) => Offset((p.dx * sx) - left, (p.dy * sy) - top)).toList()
        : const <Offset>[];

    for (var y = 0; y < roiHeight; y++) {
      final targetY = top + y;
      if (targetY < 0 || targetY >= shapeMask.height) continue;
      for (var x = 0; x < roiWidth; x++) {
        final targetX = left + x;
        if (targetX < 0 || targetX >= shapeMask.width) continue;
        if (!_pointInsideShape(shape, x, y, roiWidth, roiHeight, lassoInRoi)) continue;
        shapeMask.setPixel(targetX, targetY, img.ColorRgb8(255, 255, 255));
      }
    }

    return shapeMask;
  }

  bool _pointInsideShape(SmartInsertionShape shape, int x, int y, int width, int height, List<Offset> lassoInRoi) {
    if (shape == SmartInsertionShape.rectangle) return true;
    if (shape == SmartInsertionShape.ellipse) {
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
      final intersects = ((yi > p.dy) != (yj > p.dy)) && (p.dx < ((xj - xi) * (p.dy - yi)) / ((yj - yi) + 1e-9) + xi);
      if (intersects) inside = !inside;
      j = i;
    }
    return inside;
  }

  Future<void> _apply() async {
    if (_isApplying) return;
    final baseMask = _initialMask ?? img.Image(width: widget.baseImageWidth, height: widget.baseImageHeight);
    final mask = _strokeHistory.applyToMask(baseMask);
    final holeFreeMask = MaskUtils.fillHoles(mask);
    final featheredMask = MaskUtils.featherMaskEdges(holeFreeMask, radius: 1);
    final expandedMask = MaskUtils.dilateMaskByPercent(featheredMask, percent: 0.01);
    setState(() => _isApplying = true);
    try {
      await widget.onApply((cutoutBytes: widget.cutoutBytes, placementMask: expandedMask));
    } finally {
      if (mounted) {
        setState(() => _isApplying = false);
      }
    }
  }

  void _handleApplyPressed() {
    if (_isApplying) return;
    _apply();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: MaskEditorAppBar(
        onCancel: widget.onCancel,
        onApply: _handleApplyPressed,
        applyEnabled: (_initialMask != null || _strokeHistory.strokes.isNotEmpty) && !_isApplying,
        canUndo: _canUndo,
        canRedo: _canRedo,
        onUndo: _undo,
        onRedo: _redo,
        title: null,
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final displaySize = fitSizeWithinBounds(
                    Size(widget.baseImageWidth.toDouble(), widget.baseImageHeight.toDouble()),
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
                                child: Image.memory(widget.baseImageBytes, fit: BoxFit.cover),
                              ),
                              Positioned(
                                left: 0,
                                top: 0,
                                child: MaskWithStrokesOverlay(
                                  mask: _initialMask,
                                  strokes: _strokeHistory.strokes,
                                  displayWidth: displaySize.width,
                                  displayHeight: displaySize.height,
                                  imageWidth: widget.baseImageWidth.toDouble(),
                                  imageHeight: widget.baseImageHeight.toDouble(),
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
                              if (_isApplying)
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
                            onChanged: (v) => setState(() => _brushRadius = v),
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
                    label: 'Target',
                    icon: Icons.gesture,
                    isActive: _activeBottomAction == SmartInsertionBottomAction.target,
                    onPressed: _openShapePicker,
                  ),
                  _buildBottomActionButton(
                    label: 'Brush',
                    icon: Icons.brush,
                    isActive: _activeBottomAction == SmartInsertionBottomAction.brush,
                    onPressed: () {
                      setState(() {
                        _targetShape = null;
                        _selectedTool = SmartInsertionTool.brush;
                        _activeBottomAction = SmartInsertionBottomAction.brush;
                      });
                    },
                  ),
                  _buildBottomActionButton(
                    label: 'Eraser',
                    icon: Icons.auto_fix_off,
                    isActive: _activeBottomAction == SmartInsertionBottomAction.eraser,
                    onPressed: () {
                      setState(() {
                        _targetShape = null;
                        _selectedTool = SmartInsertionTool.eraser;
                        _activeBottomAction = SmartInsertionBottomAction.eraser;
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
    required VoidCallback onPressed,
  }) {
    final color = isActive ? Colors.white : Colors.white70;
    return FlatIconTextButton(
      label: Text(label, style: TextStyle(fontSize: 10.0, color: color)),
      icon: Icon(icon, size: 22, color: color),
      onPressed: onPressed,
    );
  }
}
