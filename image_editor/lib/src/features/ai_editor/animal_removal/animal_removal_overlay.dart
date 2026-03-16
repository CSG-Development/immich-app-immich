import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/brush_strokes.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/layout_utils.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/mask_utils.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/mask_editor_appbar.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/mask_with_strokes_overlay.dart';
import 'package:logging/logging.dart';

/// Overlay for animal removal: uses an animal/subject segmentation model to
/// detect animals, allows brush editing of the mask, then runs inpainting.
class AnimalRemovalOverlay extends StatefulWidget {
  const AnimalRemovalOverlay({
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
  State<AnimalRemovalOverlay> createState() => _AnimalRemovalOverlayState();
}

class _AnimalRemovalOverlayState extends State<AnimalRemovalOverlay> {
  static final Logger _log = Logger('AnimalRemovalOverlay');
  img.Image? _initialMask;
  bool _loading = true;
  String? _error;

  final StrokeHistory _strokeHistory = StrokeHistory();

  // Brush radius is defined in display pixels (converted to image space
  // in the shared brush utilities), so these values directly map to what
  // the user sees on screen. Keep the range relatively tight so brushes
  // are not overwhelmingly large.
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
      '[ANIMAL] Overlay init '
      'imageBytesLen=${widget.imageBytes.length} '
      'imageSize=${widget.imageWidth}x${widget.imageHeight}',
    );
    _detectAnimals();
  }

  Future<void> _detectAnimals() async {
    _log.info('[ANIMAL] Starting getSegmentationMask()');
    final startedAt = DateTime.now();
    img.Image? mask;
    try {
      mask = await widget.backgroundRemovalService.getSegmentationMask(
        widget.imageBytes,
      );
    } catch (e, st) {
      _log.severe('[ANIMAL] getSegmentationMask threw', e, st);
    }
    final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
    _log.info(
      '[ANIMAL] getSegmentationMask() completed in ${elapsedMs}ms '
      'maskNull=${mask == null}',
    );
    if (!mounted) return;
    setState(() {
      _loading = false;
      _initialMask = mask;
      _error = mask == null ? 'Failed to detect animals' : null;
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

  img.Image? _buildEffectiveMask() {
    final base = _initialMask;
    if (base == null) return null;
    final editedMask = _strokeHistory.applyToMask(base);
    final holeFreeMask = MaskUtils.fillHoles(editedMask);
    final featheredMask = MaskUtils.featherMaskEdges(
      holeFreeMask,
      radius: 1,
    );
    final expandedMask = MaskUtils.dilateMaskByPercent(
      featheredMask,
      percent: 0.02,
    );
    return expandedMask;
  }

  void _apply() {
    final expandedMask = _buildEffectiveMask();
    if (expandedMask == null) return;
    _log.info(
      '[ANIMAL] Apply pressed '
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

