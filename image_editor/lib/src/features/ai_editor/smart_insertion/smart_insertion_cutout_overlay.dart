import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image/image.dart' as img;
import 'package:image_editor/src/features/ai_editor/common/services/background_removal_service.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/mask_utils.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/smart_selection_overlay.dart';

class SmartInsertionCutoutOverlay extends StatefulWidget {
  const SmartInsertionCutoutOverlay({
    super.key,
    required this.imageBytes,
    required this.imageWidth,
    required this.imageHeight,
    required this.backgroundRemovalService,
    required this.ensureModelReady,
    required this.onApply,
    required this.onCancel,
  });

  final Uint8List imageBytes;
  final int imageWidth;
  final int imageHeight;
  final BackgroundRemovalService backgroundRemovalService;
  final Future<bool> Function() ensureModelReady;
  final void Function(Uint8List cutoutBytes) onApply;
  final VoidCallback onCancel;

  @override
  State<SmartInsertionCutoutOverlay> createState() => _SmartInsertionCutoutOverlayState();
}

class _SmartInsertionCutoutOverlayState extends State<SmartInsertionCutoutOverlay> {
  img.Image _retainLargestComponentWithSoftAlpha(
    img.Image mask, {
    int componentThreshold = 24,
  }) {
    final w = mask.width;
    final h = mask.height;
    final visited = List<bool>.filled(w * h, false);
    final labels = List<int>.filled(w * h, -1);
    final componentSizes = <int>[];
    var label = 0;

    bool isFg(int x, int y) => mask.getPixel(x, y).r.toInt() >= componentThreshold;
    int indexOf(int x, int y) => y * w + x;

    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final startIdx = indexOf(x, y);
        if (visited[startIdx] || !isFg(x, y)) continue;

        final stack = <int>[startIdx];
        visited[startIdx] = true;
        labels[startIdx] = label;
        var size = 0;

        while (stack.isNotEmpty) {
          final idx = stack.removeLast();
          final cx = idx % w;
          final cy = idx ~/ w;
          size++;

          void visit(int nx, int ny) {
            if (nx < 0 || nx >= w || ny < 0 || ny >= h) return;
            final nIdx = indexOf(nx, ny);
            if (visited[nIdx] || !isFg(nx, ny)) return;
            visited[nIdx] = true;
            labels[nIdx] = label;
            stack.add(nIdx);
          }

          visit(cx - 1, cy);
          visit(cx + 1, cy);
          visit(cx, cy - 1);
          visit(cx, cy + 1);
        }

        componentSizes.add(size);
        label++;
      }
    }

    if (componentSizes.isEmpty) return mask;

    var largestLabel = 0;
    var largestSize = componentSizes[0];
    for (var i = 1; i < componentSizes.length; i++) {
      if (componentSizes[i] > largestSize) {
        largestSize = componentSizes[i];
        largestLabel = i;
      }
    }

    final cleaned = img.Image(width: w, height: h);
    for (var y = 0; y < h; y++) {
      for (var x = 0; x < w; x++) {
        final idx = indexOf(x, y);
        final v = labels[idx] == largestLabel ? mask.getPixel(x, y).r.toInt().clamp(0, 255) : 0;
        cleaned.setPixel(x, y, img.ColorRgb8(v, v, v));
      }
    }
    return cleaned;
  }

  img.Image _trimTransparentBounds(img.Image image) {
    var minX = image.width;
    var minY = image.height;
    var maxX = -1;
    var maxY = -1;

    for (var y = 0; y < image.height; y++) {
      for (var x = 0; x < image.width; x++) {
        if (image.getPixel(x, y).a > 0) {
          if (x < minX) minX = x;
          if (y < minY) minY = y;
          if (x > maxX) maxX = x;
          if (y > maxY) maxY = y;
        }
      }
    }

    if (maxX < minX || maxY < minY) {
      return image;
    }

    final trimWidth = maxX - minX + 1;
    final trimHeight = maxY - minY + 1;
    return img.copyCrop(image, x: minX, y: minY, width: trimWidth, height: trimHeight);
  }

  img.Image _softenMaskEdges(img.Image binaryMask) {
    final feathered = MaskUtils.featherMaskEdges(binaryMask.clone(), radius: 2);
    final softened = img.Image(width: feathered.width, height: feathered.height);
    for (var y = 0; y < feathered.height; y++) {
      for (var x = 0; x < feathered.width; x++) {
        final v = feathered.getPixel(x, y).r.toInt().clamp(0, 255);
        // Keep interior solid, outside transparent, smooth only transition band.
        final mapped = v <= 12
            ? 0
            : (v >= 240 ? 255 : (((v - 12) * 255) / (240 - 12)).round().clamp(0, 255));
        softened.setPixel(x, y, img.ColorRgb8(mapped, mapped, mapped));
      }
    }
    return softened;
  }

  @override
  Widget build(BuildContext context) {
    return SmartSelectionOverlay(
      imageBytes: widget.imageBytes,
      imageWidth: widget.imageWidth,
      imageHeight: widget.imageHeight,
      backgroundRemovalService: widget.backgroundRemovalService,
      ensureModelReady: widget.ensureModelReady,
      applyDilatePercent: 0.0,
      // Match smart removal editing behavior: keep a binary mask while editing
      // for responsive brush/eraser interactions, then soften at apply time.
      softSegmentationMask: false,
      segmentationFeatherRadius: 0,
      segmentationThreshold: 0.5,
      title: 'Smart insertion',
      failureMessage: 'Failed to detect subject',
      onCancel: widget.onCancel,
      onApplyMask: (mask) async {
        final holeFreeMask = MaskUtils.fillHoles(mask.clone());
        final cleanedMask = _retainLargestComponentWithSoftAlpha(holeFreeMask);
        final softenedMask = _softenMaskEdges(cleanedMask);
        final source = img.decodeImage(widget.imageBytes);
        if (source == null) return;
        var cutout = source;
        if (source.width != softenedMask.width || source.height != softenedMask.height) {
          cutout = img.copyResize(
            source,
            width: softenedMask.width,
            height: softenedMask.height,
            interpolation: img.Interpolation.linear,
          );
        }
        if (cutout.numChannels != 4) {
          cutout = cutout.convert(numChannels: 4);
        }
        for (var y = 0; y < softenedMask.height; y++) {
          for (var x = 0; x < softenedMask.width; x++) {
            final maskV = softenedMask.getPixel(x, y).r.toInt().clamp(0, 255);
            final px = cutout.getPixel(x, y);
            cutout.setPixel(
              x,
              y,
              img.ColorRgba8(
                px.r.toInt(),
                px.g.toInt(),
                px.b.toInt(),
                maskV,
              ),
            );
          }
        }
        final trimmedCutout = _trimTransparentBounds(cutout);
        widget.onApply(Uint8List.fromList(img.encodePng(trimmedCutout)));
      },
    );
  }
}
