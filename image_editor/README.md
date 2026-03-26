# image_editor

A Flutter image editor package that extends [`pro_image_editor`](https://pub.dev/packages/pro_image_editor) with additional tools such as **vignette** and **AI‑powered editing** (background blur, denoise, object removal, people removal, smart insertion). It is designed as an embeddable editor for mobile and desktop applications.

## What this package provides

- **Full image editor UI** built on top of `pro_image_editor`
- **Vignette editor** with radial controls (intensity, radius, feather, color) that are baked into the final image
- **AI tools** (native platforms only):
  - **Background blur** – keep the subject sharp, blur the rest
  - **Denoise** – reduce noise using ONNX denoisers (e.g. FastDVDnet)
  - **Object removal** – remove painted regions via inpainting (LaMa)
  - **People removal** – segment and remove people (MODNet + LaMa)
  - **Smart insertion** – cut out a subject, place it into a target area, and harmonize destination with AI inpaint

## Quick start

Add the package to your app’s `pubspec.yaml`:

```yaml
dependencies:
  image_editor:
    path: ../image_editor  # or your own package location
```

Use the bundled editor widget in your app:

```dart
import 'package:image_editor/image_editor.dart';

Navigator.of(context).push(
  MaterialPageRoute(
    builder: (context) => ImageEditor(
      config: ImageEditorConfig(
        imageBytes: imageBytes,
        onImageEditingComplete: (bytes) {
          // Handle the edited image (save, share, etc.)
        },
        onCloseEditor: () => Navigator.of(context).pop(),
        theme: ThemeData.dark(),
        enableTuneAdjustments: true,
      ),
    ),
  ),
);
```

## AI runtime setup (host app)

AI features are powered by `flutter_onnxruntime`. Because this package is a library, platform‑specific wiring must be done in the **host application**.

- **Android**: add ProGuard keep rules for `ai.onnxruntime.**` in `android/app/proguard-rules.pro`
- **iOS**:
  - In your Xcode build settings set `STRIP_INSTALLED_PRODUCT = NO` and `STRIP_STYLE = non-global`
- **Web**: not supported at the moment

Web builds are not supported for this package right now; only Android and iOS are expected to work.

## AI models (high‑level)

Models are configured via `AiEditorInitConfigs` using either **local assets** or **remote URLs**:

- **Object removal** – LaMa inpainting model
- **Background / people** – MODNet foreground/background separation
- **Denoise** – FastDVDnet backend
- **Smart insertion cutout** – background-removal segmentation model (soft-mask mode with higher cutout quality presets)

On iOS and Android, remote models are downloaded on first use and cached.

## Smart insertion notes

Smart insertion has two stages:

1. **Cutout stage** (segmentation-based)
   - Uses soft mask settings to improve edge quality
   - Trims transparent bounds so empty padding does not affect placement scale
2. **Placement stage** (AI-assisted)
   - Uses the placement mask as target region
   - Preserves inserted subject aspect ratio during scaling
   - Uses inpainting on the destination preparation path to improve blend quality

### Quality-related defaults

- Cutout mask dilation is disabled for smart insertion (`applyDilatePercent = 0.0`)
- Segmentation mask for smart insertion uses soft alpha mode with light feathering
- A dedicated higher-resolution segmentation service is used in smart insertion flow

These defaults are scoped to smart insertion so object-removal behavior is not changed.

## Inpainting stability / memory behavior

LaMa ONNX in this package uses fixed `512x512` model input for compatibility with the provided model export.

To reduce RAM pressure on large edits:

- ROI expansion is conservative (smaller expansion than older defaults)
- Large ROIs use a **tiled low-memory inpaint path** with overlap
- Optional ROI-area guard can be enabled by caller for memory-sensitive flows (used by smart insertion prep, not by object removal by default)

If target devices are still memory-constrained, prefer swapping to a compatible smaller/quantized model export rather than changing input tensor size at runtime.

## Architecture in brief

From a code perspective the package is a thin layer on top of `pro_image_editor`:

- A single public entry point: `ImageEditor`
- Feature pages (vignette, AI editor) that open on top of the main editor
- Shared init‑config objects (e.g. `VignetteEditorInitConfigs`, `AiEditorInitConfigs`) so sub‑editors see the same image, transforms and theme
- Reusable UI primitives (editor bottom bar, adjustment bottom bar, overlays)
- AI services that wrap ONNX models and are orchestrated by the `AiEditor`

To add a new tool, you typically:

1. Add any feature‑specific fields to an `EditorInitConfigs` implementation
2. Build a feature page that receives the current image and state, shows controls, and returns a baked `Uint8List`
3. Wire a button in the bottom bar that captures the current editor image and pushes your page

## Watermark tool implementation

The watermark tool is implemented as a live `WidgetLayer` on top of `pro_image_editor`:

- The tool is opened from `EditorBottomBar` and receives `ProImageEditorState`
- A dedicated layer is tracked with `groupId: custom-watermark-layer`
- Control changes (text/logo/mode/position/opacity/size/angle/color) rebuild that layer immediately
- `Apply` keeps the current layer; `Cancel` restores the previous watermark layer (if there was one)

For export consistency, the watermark layer uses the same sizing model as stickers:

- Base content is built in a canvas with width `stickerEditor.initWidth`
- Layer `scale` is computed from fitted image width (`fit.width / initWidth`)
- Layer `offset` compensates `stickerEditor.layerFractionalOffset` so placement matches editor anchor rules

Web behavior:

- `Logo` and `Text + Logo` modes are disabled on web (no gallery picking flow in this package path)
- `Text` mode remains available

## Public API surface

- `ImageEditor` – main editor widget
- `EditorBottomBar` – toolbar hosting core and custom tools
- `ImageEditorConfig` – configuration supplied by the host app
- `ImageEffect` / `MonochromeEffect` – simple effect interfaces / examples
- `color_matrix_utils`, `tune_adjustment_matrices` – low‑level utilities

## License

See the repository root for license and contribution guidelines.
