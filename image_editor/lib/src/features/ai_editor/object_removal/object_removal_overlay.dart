import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/brush_strokes.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/layout_utils.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/mask_utils.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/mask_editor_appbar.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/mask_stroke_overlay.dart';

/// Overlay for drawing a mask (brush strokes) on an image to mark areas for
/// object removal. Converts screen coordinates to image coordinates.
class ObjectRemovalOverlay extends StatefulWidget {
  const ObjectRemovalOverlay({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.onApply,
    required this.onCancel,
  });

  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final void Function(img.Image mask) onApply;
  final VoidCallback onCancel;

  @override
  State<ObjectRemovalOverlay> createState() => _ObjectRemovalOverlayState();
}

class _ObjectRemovalOverlayState extends State<ObjectRemovalOverlay> {
  final StrokeHistory _strokeHistory = StrokeHistory();
  // Brush radius is defined in display pixels (converted to image space
  // in the shared brush utilities), so keep this range modest so the
  // brush feels precise across image resolutions.
  static const double _minBrushRadius = 6.0;
  static const double _maxBrushRadius = 48.0;
  double _brushRadius = 24.0;

  bool _isAddMode = true;

  bool get _canUndo => _strokeHistory.canUndo;
  bool get _canRedo => _strokeHistory.canRedo;

  void _onPanStart(Offset localPosition, Size displaySize) {
    setState(() {
      _strokeHistory.startBatch(_isAddMode);
      _addStrokePoint(localPosition, displaySize);
    });
  }

  void _addStroke(Offset localPosition, Size displaySize) {
    setState(() {
      _addStrokePoint(localPosition, displaySize);
    });
  }

  void _addStrokePoint(Offset localPosition, Size displaySize) {
    final stroke = createStrokeFromLocalPosition(
      localPosition: localPosition,
      displaySize: displaySize,
      imageWidth: widget.imageWidth,
      imageHeight: widget.imageHeight,
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
    final baseMask = img.Image(
      width: widget.imageWidth,
      height: widget.imageHeight,
    );
    final strokedMask = _strokeHistory.applyToMask(baseMask);
    final holeFreeMask = MaskUtils.fillHoles(strokedMask);
    final featheredMask = MaskUtils.featherMaskEdges(
      holeFreeMask,
      radius: 1,
    );
    // Match the people-removal pipeline: slightly expand the mask so the
    // inpainting area over-covers the drawn region and avoids harsh seams.
    final expandedMask = MaskUtils.dilateMaskByPercent(
      featheredMask,
      percent: 0.02,
    );
    widget.onApply(expandedMask);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: MaskEditorAppBar(
        onCancel: widget.onCancel,
        onApply: _apply,
        applyEnabled: !_strokeHistory.strokes.isEmpty,
        canUndo: _canUndo,
        canRedo: _canRedo,
        onUndo: _undo,
        onRedo: _redo,
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

                  return Center(
                    child: GestureDetector(
                      onPanStart: (d) => _onPanStart(
                        d.localPosition,
                        displaySize,
                      ),
                      onPanUpdate: (d) => _addStroke(
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
                              widget.imageBytes,
                              fit: BoxFit.cover,
                            ),
                          ),
                          Positioned(
                            left: 0,
                            top: 0,
                            child: MaskStrokeOverlay(
                              strokes: _strokeHistory.strokes,
                              displayWidth: displaySize.width,
                              displayHeight: displaySize.height,
                              imageWidth: widget.imageWidth.toDouble(),
                              imageHeight: widget.imageHeight.toDouble(),
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    icon: const Icon(Icons.brush),
                    color: _isAddMode ? Colors.white : Colors.white54,
                    onPressed: () {
                      setState(() {
                        _isAddMode = true;
                      });
                    },
                  ),
                  IconButton(
                    icon: const Icon(Icons.auto_fix_off),
                    color: !_isAddMode ? Colors.white : Colors.white54,
                    onPressed: () {
                      setState(() {
                        _isAddMode = false;
                      });
                    },
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
            ),
          ],
        ),
      ),
    );
  }
}

