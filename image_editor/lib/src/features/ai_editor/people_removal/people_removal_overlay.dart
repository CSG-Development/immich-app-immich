import 'dart:math' as math;
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/layout_utils.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/brush_strokes.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/mask_editor_appbar.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/mask_with_strokes_overlay.dart';
import 'package:image_editor/src/features/services/image_worker.dart';
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
  // Remember the last stroke in the current drag so we can interpolate
  // intermediate strokes and avoid dotted lines, especially for small
  // brush sizes.
  BrushStroke? _lastStrokeForCurrentDrag;

  // Brush radius is defined in display pixels (converted to image space
  // in the shared brush utilities). Match the object/animal removal
  // range so the experience is consistent across tools.
  static const double _minBrushRadius = 6.0;
  static const double _maxBrushRadius = 48.0;
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
      _lastStrokeForCurrentDrag = null;
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
    final base = _initialMask;
    if (base == null) return;

    final startedAt = DateTime.now();
    _log.info(
      '[PEOPLE] Apply tapped '
      'baseMask=${base.width}x${base.height} '
      'imageSize=${widget.imageWidth}x${widget.imageHeight} '
      'strokes=${_strokeHistory.strokes.length}',
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

    final baseData = Uint8List(base.width * base.height);
    var idx = 0;
    for (var y = 0; y < base.height; y++) {
      for (var x = 0; x < base.width; x++) {
        final p = base.getPixel(x, y);
        baseData[idx++] = p.r.toInt().clamp(0, 255);
      }
    }

    final maskData = await ImageWorker.instance.buildStrokeMask(
      width: widget.imageWidth,
      height: widget.imageHeight,
      strokes: strokesPayload,
      baseMask: <String, Object>{
        'width': base.width,
        'height': base.height,
        'data': baseData,
      },
    );
    final workerElapsed =
        DateTime.now().difference(startedAt).inMilliseconds;
    _log.info(
      '[PEOPLE] buildStrokeMask completed in ${workerElapsed}ms',
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

    final expandedMask = img.Image(width: width, height: height);
    var idxOut = 0;
    for (var y = 0; y < height; y++) {
      for (var x = 0; x < width; x++) {
        final v = data[idxOut++];
        expandedMask.setPixel(x, y, img.ColorRgb8(v, v, v));
      }
    }

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

    return Scaffold(
      backgroundColor: Colors.black87,
      appBar: MaskEditorAppBar(
        onCancel: widget.onCancel,
        onApply: _apply,
        applyEnabled: _initialMask != null,
        canUndo: _canUndo,
        canRedo: _canRedo,
        onUndo: _undo,
        onRedo: _redo,
      ),
      body: SafeArea(
        child: Column(
          children: [
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
                                      child: MaskWithStrokesOverlay(
                                        mask: _initialMask,
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
            if (!_loading && _initialMask != null)
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
              ),
          ],
        ),
      ),
    );
  }
}

