import 'dart:async';
import 'dart:isolate';
import 'dart:math' as math;

import 'package:flutter/foundation.dart';
import 'package:image/image.dart' as img;
import 'package:logging/logging.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/mask_utils.dart';

final Logger _imageWorkerLog = Logger('ImageWorker');

/// Shared background image worker.
///
/// - On mobile/desktop: runs heavy pure-Dart image work in a dedicated isolate.
/// - On web: falls back to running the same code on the main isolate (isolates
///   are limited in Flutter Web and plugin calls must remain on main anyway).
class ImageWorker {
  ImageWorker._();

  static final ImageWorker instance = ImageWorker._();

  Isolate? _isolate;
  SendPort? _sendPort;
  int _lastRequestId = 0;
  final Map<int, Completer<dynamic>> _pending = {};

  Future<void> _ensureIsolate() async {
    if (kIsWeb) return; // No dedicated isolate on web.
    if (_isolate != null && _sendPort != null) return;

    final readyPort = ReceivePort();
    _imageWorkerLog.info('[ImageWorker] Spawning isolate');
    _isolate = await Isolate.spawn<_ImageWorkerBootstrapMessage>(
      _imageWorkerMain,
      _ImageWorkerBootstrapMessage(readyPort.sendPort),
    );
    _sendPort = await readyPort.first as SendPort;
    _imageWorkerLog.info('[ImageWorker] Isolate ready');
  }

  Future<T?> _runJob<T>(String type, Object payload) async {
    if (kIsWeb) {
      // Web fallback: execute handlers directly on main isolate.
      return _handleJob(type, payload) as T?;
    }

    await _ensureIsolate();
    final sendPort = _sendPort;
    if (sendPort == null) return null;

    final id = ++_lastRequestId;
    _imageWorkerLog.fine('[ImageWorker] Sending job "$type" id=$id');
    final completer = Completer<dynamic>();
    _pending[id] = completer;

    final responsePort = ReceivePort();
    responsePort.listen((message) {
      if (message is List && message.length == 3 && message[0] == id) {
        final success = message[1] as bool;
        final data = message[2];
        responsePort.close();
        final c = _pending.remove(id);
        if (c == null) return;
        if (success) {
          c.complete(data);
        } else {
          c.completeError(data ?? 'ImageWorker job failed');
        }
      }
    });

    sendPort.send(<Object?>[id, type, payload, responsePort.sendPort]);
    try {
      final result = await completer.future;
      return result as T?;
    } catch (e, st) {
      _imageWorkerLog.severe('[ImageWorker] Job "$type" failed', e, st);
      return null;
    }
  }

  /// Denoise preprocessing: returns tensor + original image size.
  Future<({Float32List tensor, int originalWidth, int originalHeight})?> denoisePreprocess(
    Uint8List imageBytes,
    int modelSize,
  ) async {
    final result = await _runJob<Map<String, Object?>>('denoise_preprocess', <String, Object>{
      'bytes': imageBytes,
      'modelSize': modelSize,
    });
    if (result == null) return null;
    return (
      tensor: result['tensor'] as Float32List,
      originalWidth: result['originalWidth'] as int,
      originalHeight: result['originalHeight'] as int,
    );
  }

  /// Denoise postprocessing: returns final PNG bytes.
  Future<Uint8List?> denoisePostprocess(
    List<dynamic> outputList,
    List<int> shape,
    int originalWidth,
    int originalHeight,
  ) async {
    final result = await _runJob<Uint8List>('denoise_postprocess', <String, Object>{
      'outputList': outputList,
      'shape': shape,
      'originalWidth': originalWidth,
      'originalHeight': originalHeight,
    });
    return result;
  }

  /// Background removal mask application: applies a 1- or 3-channel model
  /// output to the original image and returns encoded bytes.
  Future<Uint8List?> backgroundApplyMask({
    required Uint8List imageBytes,
    required List<dynamic> outputList,
    required List<int> shape,
    required String mode, // 'remove' or 'blur'
    required int blurRadius,
  }) async {
    return _runJob<Uint8List>('bg_apply_mask', <String, Object>{
      'bytes': imageBytes,
      'outputList': outputList,
      'shape': shape,
      'mode': mode,
      'blurRadius': blurRadius,
    });
  }

  /// Builds an inpainting mask from user strokes (and optional base mask)
  /// entirely in the background isolate and returns a lightweight serialized
  /// representation: `{ 'width': int, 'height': int, 'data': Uint8List }`.
  ///
  /// This is used by object/people removal overlays so that "Apply" does not
  /// block the UI thread on large images.
  Future<Map<String, Object>?> buildStrokeMask({
    required int width,
    required int height,
    required List<Map<String, Object>> strokes,
    Map<String, Object>? baseMask,
  }) async {
    return _runJob<Map<String, Object>>('build_stroke_mask', <String, Object?>{
      'width': width,
      'height': height,
      'strokes': strokes,
      'baseMask': baseMask,
    });
  }

  /// Vignette baking: applies a radial vignette and returns encoded bytes.
  Future<Uint8List?> vignetteBake(
    Uint8List imageBytes, {
    required double intensity,
    required double radius,
    required double feather,
    int? colorHex,
  }) async {
    return _runJob<Uint8List>('vignette_bake', <String, Object?>{
      'bytes': imageBytes,
      'intensity': intensity,
      'radius': radius,
      'feather': feather,
      'colorHex': colorHex ?? 0x000000,
    });
  }

  Future<void> dispose() async {
    if (_isolate != null) {
      _sendPort?.send(<Object?>[-1, 'shutdown', const <String, Object>{}, null]);
      _isolate?.kill(priority: Isolate.immediate);
    }
    _isolate = null;
    _sendPort = null;
    _pending.clear();
  }
}

class _ImageWorkerBootstrapMessage {
  const _ImageWorkerBootstrapMessage(this.sendPort);
  final SendPort sendPort;
}

void _imageWorkerMain(_ImageWorkerBootstrapMessage bootstrap) {
  final port = ReceivePort();
  bootstrap.sendPort.send(port.sendPort);

  port.listen((message) async {
    if (message is! List || message.length != 4) return;
    final int id = message[0] as int;
    final String type = message[1] as String;
    final Object payload = message[2] as Object;
    final SendPort? replyPort = message[3] as SendPort?;

    if (id == -1 && type == 'shutdown') {
      port.close();
      return;
    }

    if (replyPort == null) return;

    try {
      final result = await _handleJob(type, payload);
      replyPort.send(<Object?>[id, true, result]);
    } catch (e, st) {
      _imageWorkerLog.severe('[ImageWorker] Error in job "$type"', e, st);
      replyPort.send(<Object?>[id, false, e.toString()]);
    }
  });
}

Future<Object?> _handleJob(String type, Object payload) async {
  switch (type) {
    case 'denoise_preprocess':
      return _handleDenoisePreprocess(payload);
    case 'denoise_postprocess':
      return _handleDenoisePostprocess(payload);
    case 'vignette_bake':
      return _handleVignetteBake(payload);
    case 'bg_apply_mask':
      return _handleBackgroundMaskApply(payload);
    default:
      throw UnsupportedError('Unknown ImageWorker job type: $type');
  }
}

Future<Map<String, Object>> _handleBuildStrokeMask(Object payload) async {
  final map = payload as Map<Object?, Object?>;
  final startedAt = DateTime.now();
  final width = map['width'] as int;
  final height = map['height'] as int;
  final strokesPayload = (map['strokes'] as List).cast<Map<Object?, Object?>>();
  final baseMaskMap = map['baseMask'] as Map<Object?, Object?>?;

  // Work in a downscaled coordinate space so that very large images do not
  // require building and post-processing huge masks. Keep aspect ratio but
  // clamp the longest side to 512px.
  const int maxSide = 512;
  final double scale = (width <= maxSide && height <= maxSide) ? 1.0 : (maxSide / math.max(width, height));
  final int workW = (width * scale).round().clamp(1, width);
  final int workH = (height * scale).round().clamp(1, height);
  _imageWorkerLog.info('[MASK_WORKER] Using working mask size ${workW}x$workH for original ${width}x$height');

  img.Image baseMask = img.Image(width: workW, height: workH);
  if (baseMaskMap != null) {
    _imageWorkerLog.info('[MASK_WORKER] Reconstructing base mask in isolate...');
    final baseStart = DateTime.now();
    final bw = baseMaskMap['width'] as int? ?? width;
    final bh = baseMaskMap['height'] as int? ?? height;
    final data = baseMaskMap['data'] as Uint8List?;
    if (data != null && data.length == bw * bh) {
      baseMask = img.Image(width: bw, height: bh);
      var idx = 0;
      for (var y = 0; y < bh; y++) {
        for (var x = 0; x < bw; x++) {
          final v = data[idx++];
          baseMask.setPixel(x, y, img.ColorRgb8(v, v, v));
        }
      }
      if (bw != workW || bh != workH) {
        _imageWorkerLog.info('[MASK_WORKER] Resizing base mask from ${bw}x$bh to ${workW}x$workH');
        baseMask = img.copyResize(baseMask, width: workW, height: workH, interpolation: img.Interpolation.nearest);
      }
    }
    final baseElapsed = DateTime.now().difference(baseStart).inMilliseconds;
    _imageWorkerLog.info('[MASK_WORKER] Base mask reconstruction took ${baseElapsed}ms');
  }

  _imageWorkerLog.info('[MASK_WORKER] Applying ${strokesPayload.length} strokes...');
  final strokesStart = DateTime.now();

  final mask = baseMask.clone();
  final w = mask.width;
  final h = mask.height;

  for (final raw in strokesPayload) {
    final originalX = (raw['x'] as num).toDouble();
    final originalY = (raw['y'] as num).toDouble();
    final originalR = (raw['radius'] as num).toDouble();

    final scaledX = originalX * scale;
    final scaledY = originalY * scale;
    final scaledR = originalR * scale;

    final cx = scaledX.round();
    final cy = scaledY.round();
    final r = scaledR.round().clamp(1, 200);
    final r2 = r * r;
    final isAdd = (raw['isAdd'] as bool?) ?? true;
    final color = isAdd ? img.ColorRgb8(255, 255, 255) : img.ColorRgb8(0, 0, 0);

    for (var dy = -r; dy <= r; dy++) {
      for (var dx = -r; dx <= r; dx++) {
        if (dx * dx + dy * dy <= r2) {
          final x = cx + dx;
          final y = cy + dy;
          if (x >= 0 && x < w && y >= 0 && y < h) {
            mask.setPixel(x, y, color);
          }
        }
      }
    }
  }

  final strokesElapsed = DateTime.now().difference(strokesStart).inMilliseconds;
  _imageWorkerLog.info('[MASK_WORKER] Stroke application took ${strokesElapsed}ms');

  final postStart = DateTime.now();
  final holeFreeMask = MaskUtils.fillHoles(mask);
  final featheredMask = MaskUtils.featherMaskEdges(holeFreeMask, radius: 1);
  final expandedMask = MaskUtils.dilateMaskByPercent(featheredMask, percent: 0.02);
  final postElapsed = DateTime.now().difference(postStart).inMilliseconds;
  _imageWorkerLog.info('[MASK_WORKER] Post-process (fill/feather/dilate) took ${postElapsed}ms');

  final packStart = DateTime.now();
  // Upscale the working mask back to the original image dimensions.
  final upscaledMask = (workW == width && workH == height)
      ? expandedMask
      : img.copyResize(expandedMask, width: width, height: height, interpolation: img.Interpolation.nearest);

  final out = Uint8List(width * height);
  var idxOut = 0;
  for (var y = 0; y < upscaledMask.height; y++) {
    for (var x = 0; x < upscaledMask.width; x++) {
      final p = upscaledMask.getPixel(x, y);
      out[idxOut++] = p.r.toInt().clamp(0, 255);
    }
  }
  final packElapsed = DateTime.now().difference(packStart).inMilliseconds;

  final totalElapsed = DateTime.now().difference(startedAt).inMilliseconds;
  _imageWorkerLog.info(
    '[MASK_WORKER] buildStrokeMask total=${totalElapsed}ms '
    '(strokes=${strokesElapsed}ms, post=$postElapsed ms, pack=${packElapsed}ms)',
  );

  return <String, Object>{'width': width, 'height': height, 'data': out};
}

Future<Map<String, Object?>> _handleDenoisePreprocess(Object payload) async {
  final map = payload as Map<Object?, Object?>;
  final bytes = map['bytes'] as Uint8List;
  final modelSize = map['modelSize'] as int;

  final decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('[DENOISE] Preprocess: failed to decode image.');
  }

  final originalWidth = decoded.width;
  final originalHeight = decoded.height;
  _imageWorkerLog.info('[DENOISE] Preprocess(worker): original size ${originalWidth}x$originalHeight');

  final rgbImage = decoded.numChannels == 3 ? decoded : decoded.convert(numChannels: 3);

  final resized = img.copyResize(
    rgbImage,
    width: modelSize,
    height: modelSize,
    interpolation: img.Interpolation.linear,
  );

  final tensor = _denoiseImageToFloat32NCHW(resized);

  return <String, Object?>{'tensor': tensor, 'originalWidth': originalWidth, 'originalHeight': originalHeight};
}

Future<Uint8List> _handleDenoisePostprocess(Object payload) async {
  final map = payload as Map<Object?, Object?>;
  final outputList = map['outputList'] as List<dynamic>;
  final shape = (map['shape'] as List).cast<int>();
  final originalWidth = map['originalWidth'] as int;
  final originalHeight = map['originalHeight'] as int;

  if (shape.length != 4 || (shape[1] != 3 && shape[3] != 3)) {
    throw StateError('[DENOISE] Postprocess: unexpected output shape: $shape');
  }

  // Support both NCHW [1, 3, H, W] and NHWC [1, H, W, 3] layouts.
  final bool isNchw = shape[1] == 3;
  final outH = isNchw ? shape[2] : shape[1];
  final outW = isNchw ? shape[3] : shape[2];

  final denoised = isNchw
      ? _denoiseFloat32NCHWToImage(outputList, outW, outH)
      : _denoiseFloat32NHWCToImage(outputList, outW, outH);

  final result = img.copyResize(
    denoised,
    width: originalWidth,
    height: originalHeight,
    interpolation: img.Interpolation.linear,
  );

  return Uint8List.fromList(img.encodePng(result));
}

Future<Uint8List?> _handleVignetteBake(Object payload) async {
  final map = payload as Map<Object?, Object?>;
  final bytes = map['bytes'] as Uint8List;
  final intensity = map['intensity'] as double;
  final radius = map['radius'] as double;
  final feather = map['feather'] as double;
  final int? colorHex = map['colorHex'] as int?;

  var decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('[VIGNETTE] Failed to decode image.');
  }
  if (decoded.numChannels != 4) {
    decoded = decoded.convert(numChannels: 4);
  }

  final w = decoded.width;
  final h = decoded.height;
  final cx = w / 2.0;
  final cy = h / 2.0;
  final maxDist = math.sqrt(cx * cx + cy * cy);
  final t = radius.clamp(0.0, 1.0);

  const aspectBlend = 0.5;
  final aspect = cx / cy;
  final landscapeDelta = aspect > 1.0 ? (aspect - 1.0) : 0.0;
  final landscapeScale = landscapeDelta * aspectBlend;
  final aspectScale = 1.0 + landscapeScale;
  const baseOffsetMin = 0.03;
  const baseOffsetRange = 0.07;
  final baseOffset = baseOffsetMin + baseOffsetRange * t;
  const smallRadiusLandscapeBoostMax = 0.06;
  final smallRadiusLandscapeBoost = landscapeScale > 0
      ? smallRadiusLandscapeBoostMax * (1.0 - t) * landscapeScale
      : 0.0;

  final inner = 0.15 + 0.6 * (t * aspectScale) + baseOffset + smallRadiusLandscapeBoost;
  final soft = (0.05 + 0.35 * feather.clamp(0.0, 1.0)).clamp(0.01, 1.0);
  final i = intensity.clamp(0.0, 1.0);
  final rgb = colorHex ?? 0x000000;
  final cr = (rgb >> 16) & 0xFF;
  final cg = (rgb >> 8) & 0xFF;
  final cb = rgb & 0xFF;

  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final dx = (x - cx) / maxDist;
      final dy = (y - cy) / maxDist;
      final d = math.sqrt(dx * dx + dy * dy);
      double factor = 0.0;
      if (d > inner) factor = (((d - inner) / soft).clamp(0.0, 1.0)) * i;
      final pixel = decoded.getPixel(x, y);
      final r = (pixel.r.toDouble() * (1 - factor) + cr.toDouble() * factor).round().clamp(0, 255);
      final g = (pixel.g.toDouble() * (1 - factor) + cg.toDouble() * factor).round().clamp(0, 255);
      final b = (pixel.b.toDouble() * (1 - factor) + cb.toDouble() * factor).round().clamp(0, 255);
      final a = pixel.a.toInt().clamp(0, 255);
      decoded.setPixel(x, y, img.ColorRgba8(r, g, b, a));
    }
  }

  final isJpeg = bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

  return Uint8List.fromList(isJpeg ? img.encodeJpg(decoded) : img.encodePng(decoded));
}

Future<Uint8List> _handleBackgroundMaskApply(Object payload) async {
  final map = payload as Map<Object?, Object?>;
  final bytes = map['bytes'] as Uint8List;
  final outputList = map['outputList'] as List<dynamic>;
  final shape = (map['shape'] as List).cast<int>();
  final mode = map['mode'] as String;
  final blurRadius = map['blurRadius'] as int;

  if (shape.length != 4) {
    throw StateError('[BG_WORKER] Unexpected output rank: ${shape.length}');
  }
  final outC = shape[1];
  final outH = shape[2];
  final outW = shape[3];
  if (outH <= 0 || outW <= 0) {
    throw StateError('[BG_WORKER] Invalid output spatial size: ${outW}x$outH');
  }

  var decoded = img.decodeImage(bytes);
  if (decoded == null) {
    throw StateError('[BG_WORKER] Failed to decode input image.');
  }
  final originalWidth = decoded.width;
  final originalHeight = decoded.height;

  if (outC == 1) {
    final base = decoded.numChannels == 4 ? decoded : decoded.convert(numChannels: 4);

    final useBlur = mode == 'blur';
    final blurred = useBlur ? img.gaussianBlur(base.clone(), radius: blurRadius.clamp(1, 64)) : null;

    final result = img.Image(width: originalWidth, height: originalHeight, numChannels: 4);

    // Build a small grayscale mask from the raw model output so we can
    // fill interior holes and feather the alpha edges before upsampling.
    final rawMask = img.Image(width: outW, height: outH);
    for (var my = 0; my < outH; my++) {
      for (var mx = 0; mx < outW; mx++) {
        final midx = my * outW + mx;
        final raw = outputList[midx];
        final v = raw is num ? raw.toDouble().clamp(0.0, 1.0) : 0.0;
        final byte = (v * 255).round().clamp(0, 255);
        rawMask.setPixel(mx, my, img.ColorRgb8(byte, byte, byte));
      }
    }
    final filledMask = MaskUtils.fillHoles(rawMask);
    final featheredMask = MaskUtils.featherMaskEdges(filledMask, radius: 2);

    for (var y = 0; y < originalHeight; y++) {
      for (var x = 0; x < originalWidth; x++) {
        final mx = (x * outW / originalWidth).clamp(0, outW - 1).toInt();
        final my = (y * outH / originalHeight).clamp(0, outH - 1).toInt();
        final mp = featheredMask.getPixel(mx, my);
        final v = mp.r.toDouble().clamp(0.0, 255.0);
        // Strengthen the mask so interior foreground becomes solid (alpha=1)
        // while still allowing a small soft band around the edges.
        double weight;
        if (v >= 220) {
          weight = 1.0;
        } else if (v <= 40) {
          weight = 0.0;
        } else {
          weight = ((v - 40.0) / (220.0 - 40.0)).clamp(0.0, 1.0);
        }

        final src = base.getPixel(x, y);
        final sr = src.r.toDouble();
        final sg = src.g.toDouble();
        final sb = src.b.toDouble();

        if (useBlur && blurred != null) {
          final bp = blurred.getPixel(x, y);
          final br = bp.r.toDouble();
          final bg = bp.g.toDouble();
          final bb = bp.b.toDouble();

          final r = (weight * sr + (1 - weight) * br).round().clamp(0, 255);
          final g = (weight * sg + (1 - weight) * bg).round().clamp(0, 255);
          final b = (weight * sb + (1 - weight) * bb).round().clamp(0, 255);

          result.setPixel(x, y, img.ColorRgba8(r, g, b, 255));
        } else {
          final alpha = (weight * 255).round().clamp(0, 255);
          result.setPixel(
            x,
            y,
            img.ColorRgba8(sr.toInt().clamp(0, 255), sg.toInt().clamp(0, 255), sb.toInt().clamp(0, 255), alpha),
          );
        }
      }
    }

    final isJpeg = bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

    return Uint8List.fromList(isJpeg ? img.encodeJpg(result) : img.encodePng(result));
  }

  if (outC == 3) {
    final outImage = img.Image(width: outW, height: outH);
    var idx = 0;
    for (var y = 0; y < outH; y++) {
      for (var x = 0; x < outW; x++) {
        final r = _denoiseOutputToByte((outputList[idx++] as num).toDouble());
        final g = _denoiseOutputToByte((outputList[idx++] as num).toDouble());
        final b = _denoiseOutputToByte((outputList[idx++] as num).toDouble());
        outImage.setPixel(x, y, img.ColorRgba8(r, g, b, 255));
      }
    }

    final resizedOut = img.copyResize(
      outImage,
      width: originalWidth,
      height: originalHeight,
      interpolation: img.Interpolation.linear,
    );

    final isJpeg = bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

    return Uint8List.fromList(isJpeg ? img.encodeJpg(resizedOut) : img.encodePng(resizedOut));
  }

  throw StateError('[BG_WORKER] Unsupported channel layout: C=$outC');
}

Float32List _denoiseImageToFloat32NCHW(img.Image im) {
  const scale = 1.0 / 255.0;
  final w = im.width;
  final h = im.height;
  final pixelCount = w * h;
  final data = Float32List(3 * pixelCount);
  var idx = 0;
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final p = im.getPixel(x, y);
      data[idx] = p.r * scale;
      data[pixelCount + idx] = p.g * scale;
      data[2 * pixelCount + idx] = p.b * scale;
      idx++;
    }
  }
  return data;
}

img.Image _denoiseFloat32NCHWToImage(List<dynamic> raw, int w, int h) {
  final pixelCount = w * h;
  final out = img.Image(width: w, height: h);
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final idx = y * w + x;
      final rRaw = (raw[idx] as num).toDouble();
      final gRaw = (raw[pixelCount + idx] as num).toDouble();
      final bRaw = (raw[2 * pixelCount + idx] as num).toDouble();
      final r = _denoiseOutputToByte(rRaw);
      final g = _denoiseOutputToByte(gRaw);
      final b = _denoiseOutputToByte(bRaw);
      out.setPixel(x, y, img.ColorRgb8(r, g, b));
    }
  }
  return out;
}

int _denoiseOutputToByte(double v) {
  if (!v.isFinite) {
    return 0;
  }
  if (v > 1.0 || v < 0.0) {
    return v.round().clamp(0, 255);
  }
  return (v * 255).round().clamp(0, 255);
}

img.Image _denoiseFloat32NHWCToImage(List<dynamic> raw, int w, int h) {
  final out = img.Image(width: w, height: h);
  // NHWC layout: [1, H, W, 3]
  for (var y = 0; y < h; y++) {
    for (var x = 0; x < w; x++) {
      final base = (y * w + x) * 3;
      final rRaw = (raw[base] as num).toDouble();
      final gRaw = (raw[base + 1] as num).toDouble();
      final bRaw = (raw[base + 2] as num).toDouble();
      final r = _denoiseOutputToByte(rRaw);
      final g = _denoiseOutputToByte(gRaw);
      final b = _denoiseOutputToByte(bRaw);
      out.setPixel(x, y, img.ColorRgb8(r, g, b));
    }
  }
  return out;
}
