import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/utils/brush_strokes.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/layout_utils.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/mask_editor_appbar.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/mask_stroke_overlay.dart';
import 'package:image_editor/src/features/services/image_worker.dart';
import 'package:logging/logging.dart';

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
  static final Logger _log = Logger('ObjectRemovalOverlay');
  final StrokeHistory _strokeHistory = StrokeHistory();
  // Remember the last stroke in the current drag so we can interpolate
  // intermediate strokes and avoid dotted lines, especially for small
  // brush sizes.
  BrushStroke? _lastStrokeForCurrentDrag;
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
      _lastStrokeForCurrentDrag = null;
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

    final last = _lastStrokeForCurrentDrag;
    if (last != null) {
      final dx = stroke.x - last.x;
      final dy = stroke.y - last.y;
      final distance = math.sqrt(dx * dx + dy * dy);
      // Step size scales with brush radius so smaller brushes
      // get more densely sampled strokes, producing a solid line.
      final step = stroke.radius * 0.6;
      final steps = step > 0 ? (distance / step).ceil() : 0;

      for (var i = 1; i <= steps; i++) {
        final t = i / (steps + 1);
        final ix = last.x + dx * t;
        final iy = last.y + dy * t;
        _strokeHistory.addStroke(ix, iy, stroke.radius);
      }
    }

    _strokeHistory.addStroke(stroke.x, stroke.y, stroke.radius);
    _lastStrokeForCurrentDrag = stroke;
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

  Future<void> _apply() async {
    final startedAt = DateTime.now();
    _log.info(
      '[OBJ_OVERLAY] Apply tapped. strokes=${_strokeHistory.strokes.length} '
      'imageSize=${widget.imageWidth}x${widget.imageHeight}',
    );

    final strokesPayload = _strokeHistory.strokes
        .map(
          (s) => <String, Object>{
            'x': s.x,
            'y': s.y,
            'radius': s.radius,
            'isAdd': s.isAdd,
          },
        )
        .toList();

    final maskData = await ImageWorker.instance.buildStrokeMask(
      width: widget.imageWidth,
      height: widget.imageHeight,
      strokes: strokesPayload,
    );
    final workerElapsed =
        DateTime.now().difference(startedAt).inMilliseconds;
    _log.info(
      '[OBJ_OVERLAY] buildStrokeMask completed in ${workerElapsed}ms '
      '(strokesPayload=${strokesPayload.length})',
    );
    if (maskData == null) {
      return;
    }

    final width = maskData['width'] as int;
    final height = maskData['height'] as int;
    final data = maskData['data'] as Uint8List;

    if (data.length != width * height) {
      return;
    }

    final mask = img.Image(width: width, height: height);
    var idx = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final v = data[idx++];
        mask.setPixel(x, y, img.ColorRgb8(v, v, v));
      }
    }
    widget.onApply(mask);
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

