import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/layout_utils.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/mask_utils.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/brush_strokes.dart';
import 'package:logging/logging.dart';

/// Overlay for people removal: uses segmentation model to detect people,
/// allows brush editing of the mask, then runs inpainting.
class PeopleRemovalOverlay extends StatefulWidget {
  const PeopleRemovalOverlay({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.backgroundRemovalService,
    required this.onApply,
    required this.onCancel,
  });

  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final BackgroundRemovalService backgroundRemovalService;
  final void Function(img.Image mask) onApply;
  final VoidCallback onCancel;

  @override
  State<PeopleRemovalOverlay> createState() => _PeopleRemovalOverlayState();
}

class _PeopleRemovalOverlayState extends State<PeopleRemovalOverlay> {
  static final Logger _log = Logger('PeopleRemovalOverlay');
  img.Image? _initialMask;
  bool _loading = true;
  String? _error;

  final StrokeHistory _strokeHistory = StrokeHistory();

  static const double _minBrushRadius = 8.0;
  static const double _maxBrushRadius = 80.0;
  double _brushRadius = 24.0;
  bool _isAddMode = true;

  bool get _canUndo => _strokeHistory.canUndo;
  bool get _canRedo => _strokeHistory.canRedo;

  @override
  void initState() {
    super.initState();
    _log.info(
      '[PEOPLE] Overlay init '
      'imageBytesLen=${widget.imageBytes.length} '
      'imageSize=${widget.imageWidth}x${widget.imageHeight}',
    );
    _detectPeople();
  }

  Future<void> _detectPeople() async {
    _log.info('[PEOPLE] Starting getSegmentationMask()');
    final startedAt = DateTime.now();
    img.Image? mask;
    try {
      mask = await widget.backgroundRemovalService.getSegmentationMask(
        widget.imageBytes,
      );
    } catch (e, st) {
      _log.severe('[PEOPLE] getSegmentationMask threw', e, st);
    }
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    _log.info(
      '[PEOPLE] getSegmentationMask() completed in ${elapsedMs}ms '
      'maskNull=${mask == null}',
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _initialMask = mask;
      _error = mask == null ? 'Failed to detect people' : null;
    });
  }

  void _onPanStart(Offset localPosition, Size displaySize) {
    if (_initialMask == null) return;
    setState(() {
      _strokeHistory.startBatch(_isAddMode);
      _addStrokePoint(localPosition, displaySize);
    });
  }

  void _onPanUpdate(Offset localPosition, Size displaySize) {
    if (_initialMask == null) return;
    setState(() {
      _addStrokePoint(localPosition, displaySize);
    });
  }

  void _addStrokePoint(
    Offset localPosition,
    Size displaySize,
  ) {
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
    final base = _initialMask;
    if (base == null) return;
    final editedMask = _strokeHistory.applyToMask(base);
    // Slightly expand the mask (about 2% of the shortest side) so
    // that the inpainting area safely over-covers the subject.
    final expandedMask = MaskUtils.dilateMaskByPercent(
      editedMask,
      percent: 0.1,
    );
    _log.info(
      '[PEOPLE] Apply pressed '
      'maskSize=${expandedMask.width}x${expandedMask.height} '
      'strokes=${_strokeHistory.strokes.length}',
    );
    widget.onApply(expandedMask);
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
                        _loading
                            ? 'Detecting people…'
                            : 'Refine mask, then remove',
                        style: theme.textTheme.titleSmall?.copyWith(
                          color: Colors.white70,
                        ),
                      ),
                      TextButton(
                        onPressed: _initialMask != null ? _apply : null,
                        child: const Text('Remove'),
                      ),
                    ],
                  ),
                  if (!_loading && _initialMask != null) ...[
                    Row(
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
                            onChanged: (v) =>
                                setState(() => _brushRadius = v),
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
                ],
              ),
            ),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator())
                  : _error != null
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Text(
                              _error!,
                              style: theme.textTheme.bodyLarge?.copyWith(
                                color: Colors.white70,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        )
                      : LayoutBuilder(
                          builder: (context, constraints) {
                            final displaySize = fitSizeWithinBounds(
                              Size(
                                widget.imageWidth.toDouble(),
                                widget.imageHeight.toDouble(),
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
                                        widget.imageBytes,
                                        fit: BoxFit.cover,
                                      ),
                                    ),
                                    Positioned(
                                      left: 0,
                                      top: 0,
                                      child: _PeopleMaskOverlay(
                                        mask: _initialMask!,
                                        strokes: _strokeHistory.strokes,
                                        displayWidth: displaySize.width,
                                        displayHeight: displaySize.height,
                                        imageWidth: widget.imageWidth.toDouble(),
                                        imageHeight:
                                            widget.imageHeight.toDouble(),
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

class _PeopleMaskOverlay extends StatelessWidget {
  const _PeopleMaskOverlay({
    required this.mask,
    required this.strokes,
    required this.displayWidth,
    required this.displayHeight,
    required this.imageWidth,
    required this.imageHeight,
  });

  final img.Image mask;
  final List<ModeStroke> strokes;
  final double displayWidth;
  final double displayHeight;
  final double imageWidth;
  final double imageHeight;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      size: Size(displayWidth, displayHeight),
      painter: _PeopleMaskPainter(
        mask: mask,
        strokes: strokes,
        displayWidth: displayWidth,
        displayHeight: displayHeight,
        imageWidth: imageWidth,
        imageHeight: imageHeight,
      ),
    );
  }
}

class _PeopleMaskPainter extends CustomPainter {
  _PeopleMaskPainter({
    required this.mask,
    required this.strokes,
    required this.displayWidth,
    required this.displayHeight,
    required this.imageWidth,
    required this.imageHeight,
  });

  final img.Image mask;
  final List<ModeStroke> strokes;
  final double displayWidth;
  final double displayHeight;
  final double imageWidth;
  final double imageHeight;

  @override
  void paint(Canvas canvas, Size size) {
    final overlayRect = Offset.zero & size;
    canvas.saveLayer(overlayRect, Paint());

    final redPaint = Paint()
      ..color = Colors.red.withOpacity(0.5)
      ..style = PaintingStyle.fill;

    // Use a 1px sampling step to render a smooth mask overlay.
    const step = 1.0;
    // 1) Draw the base segmentation mask in red.
    for (var sy = 0.0; sy < displayHeight; sy += step) {
      for (var sx = 0.0; sx < displayWidth; sx += step) {
        final mx = (sx * mask.width / displayWidth).round().clamp(0, mask.width - 1);
        final my = (sy * mask.height / displayHeight).round().clamp(0, mask.height - 1);
        final p = mask.getPixel(mx, my);
        if (p.r > 0 || p.g > 0 || p.b > 0) {
          canvas.drawRect(
            Rect.fromLTWH(sx, sy, step, step),
            redPaint,
          );
        }
      }
    }

    // 2) Apply user strokes in chronological order so that the latest
    // stroke (draw or erase) wins visually.
    if (strokes.isNotEmpty) {
      final erasePaint = Paint()..blendMode = BlendMode.clear;

      for (final s in strokes) {
        final sx = s.x * displayWidth / imageWidth;
        final sy = s.y * displayHeight / imageHeight;
        final sr = s.radius * displayWidth / imageWidth;
        if (s.isAdd) {
          canvas.drawCircle(Offset(sx, sy), sr, redPaint);
        } else {
          canvas.drawCircle(Offset(sx, sy), sr, erasePaint);
        }
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _PeopleMaskPainter oldDelegate) {
    return oldDelegate.strokes.length != strokes.length;
  }
}

