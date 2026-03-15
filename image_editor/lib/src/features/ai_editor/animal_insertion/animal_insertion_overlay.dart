import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/brush_strokes.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/layout_utils.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/mask_utils.dart';

typedef AnimalInsertionResult = ({
  Uint8List animalCutoutBytes,
  img.Image placementMask,
});

/// Overlay for drawing the placement mask where an animal should be inserted.
class AnimalInsertionOverlay extends StatefulWidget {
  const AnimalInsertionOverlay({
    super.key,
    required this.baseImageBytes,
    required this.baseImageWidth,
    required this.baseImageHeight,
    required this.animalCutoutBytes,
    required this.onApply,
    required this.onCancel,
  });

  final Uint8List baseImageBytes;
  final int baseImageWidth;
  final int baseImageHeight;
  final Uint8List animalCutoutBytes;
  final void Function(AnimalInsertionResult result) onApply;
  final VoidCallback onCancel;

  @override
  State<AnimalInsertionOverlay> createState() => _AnimalInsertionOverlayState();
}

class _AnimalInsertionOverlayState extends State<AnimalInsertionOverlay> {
  final StrokeHistory _strokeHistory = StrokeHistory();

  // Brush radius is defined in display pixels (converted to image space
  // in the shared brush utilities). Use a slightly larger range than
  // removal tools since users may want broader placement areas, but
  // still keep it narrower than before.
  static const double _minBrushRadius = 8.0;
  static const double _maxBrushRadius = 72.0;
  double _brushRadius = 40.0;

  bool get _canUndo => _strokeHistory.canUndo;
  bool get _canRedo => _strokeHistory.canRedo;

  void _onPanStart(Offset localPosition, Size displaySize) {
    _strokeHistory.startBatch(true);
    _addStrokePoint(localPosition, displaySize);
    setState(() {});
  }

  void _onPanUpdate(Offset localPosition, Size displaySize) {
    _addStrokePoint(localPosition, displaySize);
    setState(() {});
  }

  void _addStrokePoint(Offset localPosition, Size displaySize) {
    final stroke = createStrokeFromLocalPosition(
      localPosition: localPosition,
      displaySize: displaySize,
      imageWidth: widget.baseImageWidth,
      imageHeight: widget.baseImageHeight,
      brushRadius: _brushRadius,
    );
    _strokeHistory.addStroke(stroke.x, stroke.y, stroke.radius);
  }

  void _undo() {
    if (!_canUndo) return;
    setState(() {
      _strokeHistory.undo();
    });
  }

  void _redo() {
    if (!_canRedo) return;
    setState(() {
      _strokeHistory.redo();
    });
  }

  void _apply() {
    final emptyMask = img.Image(
      width: widget.baseImageWidth,
      height: widget.baseImageHeight,
    );
    final mask = _strokeHistory.applyToMask(emptyMask);
    final holeFreeMask = MaskUtils.fillHoles(mask);
    final featheredMask = MaskUtils.featherMaskEdges(
      holeFreeMask,
      radius: 1,
    );
    final expandedMask = MaskUtils.dilateMaskByPercent(
      featheredMask,
      percent: 0.01,
    );
    widget.onApply((
      animalCutoutBytes: widget.animalCutoutBytes,
      placementMask: expandedMask,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Material(
      color: Colors.black87,
      child: SafeArea(
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: widget.onCancel,
                        child: const Text('Cancel'),
                      ),
                      Text(
                        'Draw where to place the animal',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      TextButton(
                        onPressed: _strokeHistory.strokes.isNotEmpty ? _apply : null,
                        child: const Text('Insert'),
                      ),
                    ],
                  ),
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      IconButton(
                        icon: const Icon(Icons.undo),
                        color: Colors.white70,
                        onPressed: _canUndo ? _undo : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.redo),
                        color: Colors.white70,
                        onPressed: _canRedo ? _redo : null,
                      ),
                      IconButton(
                        icon: const Icon(Icons.remove_circle_outline),
                        color: Colors.white70,
                        onPressed: _brushRadius > _minBrushRadius
                            ? () => setState(() {
                                  _brushRadius = (_brushRadius - 8)
                                      .clamp(_minBrushRadius, _maxBrushRadius);
                                })
                            : null,
                      ),
                      Expanded(
                        child: Slider(
                          value: _brushRadius,
                          min: _minBrushRadius,
                          max: _maxBrushRadius,
                          activeColor: Colors.white,
                          onChanged: (v) => setState(() => _brushRadius = v),
                        ),
                      ),
                      IconButton(
                        icon: const Icon(Icons.add_circle_outline),
                        color: Colors.white70,
                        onPressed: _brushRadius < _maxBrushRadius
                            ? () => setState(() {
                                  _brushRadius = (_brushRadius + 8)
                                      .clamp(_minBrushRadius, _maxBrushRadius);
                                })
                            : null,
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Expanded(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  final displaySize = fitSizeWithinBounds(
                    Size(
                      widget.baseImageWidth.toDouble(),
                      widget.baseImageHeight.toDouble(),
                    ),
                    Size(constraints.maxWidth, constraints.maxHeight),
                  );
                  return Center(
                    child: GestureDetector(
                      onPanStart: (d) => _onPanStart(
                        d.localPosition,
                        displaySize,
                      ),
                      onPanUpdate: (d) => _onPanUpdate(
                        d.localPosition,
                        displaySize,
                      ),
                      child: Stack(
                        clipBehavior: Clip.none,
                        children: [
                          SizedBox(
                            width: displaySize.width,
                            height: displaySize.height,
                            child: Image.memory(
                              widget.baseImageBytes,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            child: CustomPaint(
                              size: Size(displaySize.width, displaySize.height),
                              painter: _PlacementMaskPainter(
                                strokes: _strokeHistory.strokes,
                                displayWidth: displaySize.width,
                                displayHeight: displaySize.height,
                                imageWidth:
                                    widget.baseImageWidth.toDouble(),
                                imageHeight:
                                    widget.baseImageHeight.toDouble(),
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
          ],
        ),
      ),
    );
  }
}

class _PlacementMaskPainter extends CustomPainter {
  _PlacementMaskPainter({
    required this.strokes,
    required this.displayWidth,
    required this.displayHeight,
    required this.imageWidth,
    required this.imageHeight,
  });

  final List<ModeStroke> strokes;
  final double displayWidth;
  final double displayHeight;
  final double imageWidth;
  final double imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    if (strokes.isEmpty) return;

    final paintFill = Paint()
      ..color = Colors.green.withValues(alpha: 0.4)
      ..style = PaintingStyle.fill;

    for (final s in strokes) {
      if (!s.isAdd) continue;
      final sx = s.x * displayWidth / imageWidth;
      final sy = s.y * displayHeight / imageHeight;
      final sr = s.radius * displayWidth / imageWidth;
      canvas.drawCircle(Offset(sx, sy), sr, paintFill);
    }
  }

  @override
  bool shouldRepaint(covariant _PlacementMaskPainter oldDelegate) {
    return oldDelegate.strokes.length != strokes.length;
  }
}

