import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:image_editor/src/core/models/init_configs/ai_editor_init_configs.dart';
import 'package:image_editor/src/features/ai_editor/common/artifact_removal/artifact_mask_detector.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/mask_utils.dart';
import 'package:image_editor/src/features/ai_editor/object_removal/object_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/object_removal/smart_fill/smart_fill_service.dart';
import 'package:logging/logging.dart';

class ObjectRemovalArtifactPipeline {
  ObjectRemovalArtifactPipeline({
    required AiEditorInitConfigs initConfigs,
    required ObjectRemovalService objectRemovalService,
  }) : _initConfigs = initConfigs,
       _objectRemovalService = objectRemovalService;

  final AiEditorInitConfigs _initConfigs;
  // Smart removal no longer re-runs inpainting after the initial pass, but we
  // keep this injected dependency to preserve the pipeline interface.
  // ignore: unused_field
  final ObjectRemovalService _objectRemovalService;
  static final Logger _log = Logger('ObjectRemovalArtifactPipeline');

  Future<img.Image?> detectArtifactMask({
    required Uint8List processedBytes,
    required img.Image seedMask,
  }) async {
    final artifactMask = await _runArtifactDetectInIsolate(
      processedBytes: processedBytes,
      seedMask: seedMask,
      constraintMask: seedMask,
    );
    if (artifactMask == null) return null;
    final coverage = _maskCoverage(artifactMask);
    return coverage > _initConfigs.artifactStopCoverageRatio ? artifactMask : null;
  }

  Future<Uint8List> process({
    required Uint8List initialBytes,
    required img.Image initialSeedMask,
  }) async {
    final currentBytes = initialBytes;
    final artifactMask = await _detectArtifactsLikeButton(
      processedBytes: currentBytes,
      seedMask: initialSeedMask,
      constraintMask: initialSeedMask,
    );
    return processWithArtifactMask(
      initialBytes: currentBytes,
      initialSeedMask: initialSeedMask,
      artifactMask: artifactMask,
    );
  }

  Future<Uint8List> processWithArtifactMask({
    required Uint8List initialBytes,
    required img.Image initialSeedMask,
    required img.Image? artifactMask,
  }) async {
    const pass = 1;
    final currentBytes = initialBytes;

    if (artifactMask == null) return currentBytes;

    final artifactCoverage = _maskCoverage(artifactMask);
    final artifactArea = _maskAreaPixels(artifactMask);

    _log.info(
      '[OBJ] artifact pass=$pass seedCoverage=${(_maskCoverage(initialSeedMask) * 100).toStringAsFixed(3)}% '
      'artifactCoverage=${(artifactCoverage * 100).toStringAsFixed(3)}% '
      'artifactArea=$artifactArea',
    );

    if (artifactCoverage <= _initConfigs.artifactStopCoverageRatio) {
      return currentBytes;
    }

    // mask1: raw artifact mask from detector.
    final mask1 = artifactMask.clone();

    // Use original artifact mask for smart fill (no expansion).
    final mask2 = mask1.clone();

    final smartFillResult = await _runSmartFillInIsolate(
      baseBytes: currentBytes,
      mask: mask2,
    );
    var outBytes = smartFillResult.imageBytes;

    // Final LaMa cleanup on lightly expanded original mask.
    final lamaMask = MaskUtils.dilateMaskByPercent(
      mask1.clone(),
      percent: 0.06,
      maxRadius: 20,
    );
    final preCleanupImage = img.decodeImage(outBytes);
    if (preCleanupImage != null) {
      final cleanupImage = await _objectRemovalService.inpaintImage(
        preCleanupImage,
        lamaMask,
        maxRoiAreaRatio: _initConfigs.artifactMaxRoiAreaRatio,
        passIndex: pass + 1,
        singlePatch: true,
      );
      outBytes = Uint8List.fromList(img.encodePng(cleanupImage));
    }

    return outBytes;
  }

  double _maskCoverage(img.Image mask) {
    final total = mask.width * mask.height;
    if (total <= 0) return 0.0;
    var on = 0;
    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        final p = mask.getPixel(x, y);
        if (p.r > 0 || p.g > 0 || p.b > 0) {
          on++;
        }
      }
    }
    return on / total;
  }

  int _maskAreaPixels(img.Image mask) {
    var on = 0;
    for (var y = 0; y < mask.height; y++) {
      for (var x = 0; x < mask.width; x++) {
        final p = mask.getPixel(x, y);
        if (p.r > 0 || p.g > 0 || p.b > 0) on++;
      }
    }
    return on;
  }

  // NOTE: boundary-delta and iterative-shrink stop conditions were used by the
  // previous multi-pass "detect -> inpaint again" artifact loop. Smart removal
  // is now one-pass (detect once, smart-fill once).

  Future<img.Image?> _detectArtifactsLikeButton({
    required Uint8List processedBytes,
    required img.Image seedMask,
    required img.Image constraintMask,
  }) async {

    // Keep this parameter set in one place to avoid drift between the
    // initial pass and refinement iterations.
    Future<img.Image?> buildRealArtifactMask(img.Image currentSeed) async {
      return _runArtifactDetectInIsolate(
        processedBytes: processedBytes,
        seedMask: currentSeed,
        constraintMask: constraintMask,
      );
    }

    img.Image? artifactMask = await buildRealArtifactMask(seedMask);
    if (artifactMask == null || _maskCoverage(artifactMask) <= 0.0) {
      return artifactMask;
    }

    final components = _extractConnectedComponentMasks(artifactMask, minPixels: 6);
    if (components.length <= 1) {
      return artifactMask;
    }

    var currentMasks = List<img.Image>.from(components);
    var iteration = 0;
    const maxIterations = 5;
    while (iteration < maxIterations) {
      iteration++;
      var allStable = true;
      final nextMasks = <img.Image>[];
      for (final current in currentMasks) {
        final refined = await buildRealArtifactMask(current);
        if (refined == null) {
          nextMasks.add(current);
          allStable = false;
          continue;
        }
        final iou = _maskIoU(current, refined);
        final covA = _maskCoverage(current);
        final covB = _maskCoverage(refined);
        final covDelta = (covA - covB).abs();
        final stable = iou >= 0.82 && covDelta <= 0.02;
        if (!stable) allStable = false;
        nextMasks.add(refined);
      }
      currentMasks = nextMasks;
      if (allStable) break;
    }

    artifactMask = _orAllMasks(
      currentMasks,
      width: seedMask.width,
      height: seedMask.height,
    );
    return artifactMask;
  }

  Future<img.Image?> _runArtifactDetectInIsolate({
    required Uint8List processedBytes,
    required img.Image seedMask,
    required img.Image constraintMask,
  }) async {
    final seedBytes = Uint8List.fromList(img.encodePng(seedMask));
    final constraintBytes = Uint8List.fromList(img.encodePng(constraintMask));
    final maskBytes = await Isolate.run<Uint8List?>(() {
      final decoded = img.decodeImage(processedBytes);
      final seed = img.decodeImage(seedBytes);
      final constraint = img.decodeImage(constraintBytes);
      if (decoded == null || seed == null || constraint == null) return null;
      final out = buildArtifactMaskPreviewFromImage(
        processedImage: decoded,
        seedMask: seed,
        constraintMask: constraint,
        useSeedMaskAsRegion: true,
        mergeNearbyAreas: true,
        mergeKernelSize: 3,
        mergeSmoothSigma: 0.9,
        prioritizeColorArtifacts: true,
        colorOnlyArtifacts: true,
        finalPolishForInpaint: true,
        finalSmoothKernelSize: 7,
        finalSmoothSigma: 1.2,
        finalExpandPercent: 0.0,
        threshold: 22,
        adaptiveSensitivity: 1.2,
      );
      if (out == null) return null;
      return Uint8List.fromList(img.encodePng(out));
    });
    if (maskBytes == null) return null;
    return img.decodeImage(maskBytes);
  }

  Future<({Uint8List imageBytes, String methodName})> _runSmartFillInIsolate({
    required Uint8List baseBytes,
    required img.Image mask,
  }) async {
    final maskBytes = Uint8List.fromList(img.encodePng(mask));
    final result = await Isolate.run<({Uint8List imageBytes, String methodName})>(() {
      final base = img.decodeImage(baseBytes);
      final maskDecoded = img.decodeImage(maskBytes);
      if (base == null || maskDecoded == null) {
        return (imageBytes: baseBytes, methodName: 'decode_failed');
      }
      final smartFill = SmartFillService();
      final smartFillResult = smartFill.fillWithMethod(base: base, mask: maskDecoded);
      final bytes = Uint8List.fromList(img.encodePng(smartFillResult.image));
      return (imageBytes: bytes, methodName: smartFillResult.methodName);
    });
    return result;
  }

  List<img.Image> _extractConnectedComponentMasks(img.Image mask, {int minPixels = 1}) {
    final w = mask.width;
    final h = mask.height;
    final visited = List<bool>.filled(w * h, false);
    int idx(int x, int y) => y * w + x;

    bool isOn(int x, int y) {
      final p = mask.getPixel(x, y);
      return p.r > 0 || p.g > 0 || p.b > 0;
    }

    final components = <img.Image>[];
    final white = img.ColorRgb8(255, 255, 255);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final start = idx(x, y);
        if (visited[start] || !isOn(x, y)) {
          visited[start] = true;
          continue;
        }

        final queue = <int>[start];
        final pixels = <int>[start];
        visited[start] = true;
        var head = 0;
        while (head < queue.length) {
          final cur = queue[head++];
          final cx = cur % w;
          final cy = cur ~/ w;
          for (var yy = cy - 1; yy <= cy + 1; yy++) {
            for (var xx = cx - 1; xx <= cx + 1; xx++) {
              if (xx < 0 || xx >= w || yy < 0 || yy >= h) continue;
              final ni = idx(xx, yy);
              if (visited[ni]) continue;
              visited[ni] = true;
              if (isOn(xx, yy)) {
                queue.add(ni);
                pixels.add(ni);
              }
            }
          }
        }
        if (pixels.length < minPixels) continue;
        final out = img.Image(width: w, height: h);
        for (final p in pixels) {
          out.setPixel(p % w, p ~/ w, white);
        }
        components.add(out);
      }
    }
    return components;
  }

  img.Image _orAllMasks(List<img.Image> masks, {required int width, required int height}) {
    final out = img.Image(width: width, height: height);
    final white = img.ColorRgb8(255, 255, 255);
    for (final m in masks) {
      final w = width < m.width ? width : m.width;
      final h = height < m.height ? height : m.height;
      for (var y = 0; y < h; y++) {
        for (var x = 0; x < w; x++) {
          final p = m.getPixel(x, y);
          if (p.r > 0 || p.g > 0 || p.b > 0) {
            out.setPixel(x, y, white);
          }
        }
      }
    }
    return out;
  }

  double _maskIoU(img.Image a, img.Image b) {
    final w = a.width < b.width ? a.width : b.width;
    final h = a.height < b.height ? a.height : b.height;
    if (w <= 0 || h <= 0) return 0.0;
    var inter = 0;
    var union = 0;
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final pa = a.getPixel(x, y);
        final pb = b.getPixel(x, y);
        final onA = pa.r > 0 || pa.g > 0 || pa.b > 0;
        final onB = pb.r > 0 || pb.g > 0 || pb.b > 0;
        if (onA && onB) inter++;
        if (onA || onB) union++;
      }
    }
    if (union == 0) return 1.0;
    return inter / union;
  }
}
