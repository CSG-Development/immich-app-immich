/// Translations used by the custom image editor package.
///
/// Host apps can pass a partial instance; any missing value falls back to
/// built-in English defaults.
class ImageEditorTranslations {
  final String back;
  final String undo;
  final String redo;
  final String done;
  final String apply;

  final String noImageToEdit;

  final String toolPaint;
  final String toolText;
  final String toolWatermark;
  final String toolVignette;
  final String toolAi;
  final String toolCropRotate;
  final String toolTune;
  final String toolFilter;
  final String toolBlur;
  final String toolEmoji;

  final String tuneBrilliance;
  final String tuneVibrance;
  final String tuneTint;
  final String tuneHighlights;
  final String tuneShadows;

  final String aiToolsTitle;
  final String aiEditorTitle;
  final String aiToolsUnavailableOnWeb;
  final String aiToolsCurrentlyUnavailableOnWeb;
  final String failedToDecodeImage;

  final String close;
  final String cancel;
  final String download;
  final String downloading;
  final String skip;
  final String remove;

  final String aiSmartRemoval;
  final String aiEnhance;
  final String aiSmartInsertion;
  final String aiSmartInsertionInpaint;
  final String aiSelectionTooSmall;
  final String aiLassoMinPoints;
  final String aiSelectTargetShape;
  final String aiShapeRectangle;
  final String aiShapeEllipse;
  final String aiShapeLasso;
  final String aiSmart;
  final String aiTarget;
  final String aiBrush;
  final String aiEraser;
  final String aiFailedRemoveObject;
  final String aiArtifactsDetectedTitle;
  final String aiArtifactsDetectedBody;
  final String aiModelNotFoundTitle;
  final String aiModelNotFoundBody;
  final String aiDownloadModelTitle;
  final String aiDownloadModelBody;
  final String aiDownloadingModelTitle;
  final String aiFailedDetectSubject;

  final String watermarkDefaultText;
  final String watermarkTextLabel;
  final String watermarkPickLogo;
  final String watermarkRemoveLogo;
  final String watermarkOpacity;
  final String watermarkAngle;
  final String watermarkSize;
  final String watermarkPositionLabel;
  final String watermarkModeLabel;
  final String watermarkSelectPosition;
  final String watermarkSelectMode;
  final String watermarkLogoModesUnavailableWeb;
  final String watermarkPositionTopLeft;
  final String watermarkPositionTopRight;
  final String watermarkPositionBottomLeft;
  final String watermarkPositionBottomRight;
  final String watermarkPositionCenter;
  final String watermarkPositionPatternGrid;
  final String watermarkModeText;
  final String watermarkModeLogo;
  final String watermarkModeTextLogo;

  const ImageEditorTranslations({
    this.back = 'Back',
    this.undo = 'Undo',
    this.redo = 'Redo',
    this.done = 'Done',
    this.apply = 'Apply',
    this.noImageToEdit = 'No image to edit. Load an image first.',
    this.toolPaint = 'Paint',
    this.toolText = 'Text',
    this.toolWatermark = 'Watermark',
    this.toolVignette = 'Vignette',
    this.toolAi = 'AI',
    this.toolCropRotate = 'Crop/Rotate',
    this.toolTune = 'Tune',
    this.toolFilter = 'Filter',
    this.toolBlur = 'Blur',
    this.toolEmoji = 'Emoji',
    this.tuneBrilliance = 'Brilliance',
    this.tuneVibrance = 'Vibrance',
    this.tuneTint = 'Tint',
    this.tuneHighlights = 'Highlights',
    this.tuneShadows = 'Shadows',
    this.aiToolsTitle = 'AI Tools',
    this.aiEditorTitle = 'AI editor',
    this.aiToolsUnavailableOnWeb = 'AI tools are unavailable on web.',
    this.aiToolsCurrentlyUnavailableOnWeb = 'AI tools are currently unavailable on web.',
    this.failedToDecodeImage = 'Failed to decode image.',
    this.close = 'Close',
    this.cancel = 'Cancel',
    this.download = 'Download',
    this.downloading = 'Downloading...',
    this.skip = 'Skip',
    this.remove = 'Remove',
    this.aiSmartRemoval = 'Smart removal',
    this.aiEnhance = 'Enhance',
    this.aiSmartInsertion = 'Smart insertion',
    this.aiSmartInsertionInpaint = 'Smart insertion inpaint',
    this.aiSelectionTooSmall = 'Selection is too small. Draw a larger target.',
    this.aiLassoMinPoints = 'Lasso needs at least 3 points.',
    this.aiSelectTargetShape = 'Select target shape',
    this.aiShapeRectangle = 'Rectangle',
    this.aiShapeEllipse = 'Ellipse',
    this.aiShapeLasso = 'Lasso',
    this.aiSmart = 'Smart',
    this.aiTarget = 'Target',
    this.aiBrush = 'Brush',
    this.aiEraser = 'Eraser',
    this.aiFailedRemoveObject =
        'Failed to remove object (check that lama_fp32.onnx is available).',
    this.aiArtifactsDetectedTitle = 'Artifacts detected',
    this.aiArtifactsDetectedBody =
        'Try to remove detected artifacts automatically?\n\nWarning: automatic artifact cleanup can be unpredictable and may make the result worse in some cases.',
    this.aiModelNotFoundTitle = 'Model not found',
    this.aiModelNotFoundBody =
        'The required model was not found. Please provide a valid model asset/path and try again.',
    this.aiDownloadModelTitle = 'Download model?',
    this.aiDownloadModelBody =
        'This model is required for this feature. It will be downloaded and stored on your device. This may use mobile data.',
    this.aiDownloadingModelTitle = 'Downloading model',
    this.aiFailedDetectSubject = 'Failed to detect subject',
    this.watermarkDefaultText = 'Your Name',
    this.watermarkTextLabel = 'Watermark text',
    this.watermarkPickLogo = 'Pick logo',
    this.watermarkRemoveLogo = 'Remove logo',
    this.watermarkOpacity = 'Opacity',
    this.watermarkAngle = 'Angle',
    this.watermarkSize = 'Size',
    this.watermarkPositionLabel = 'Position',
    this.watermarkModeLabel = 'Mode',
    this.watermarkSelectPosition = 'Select position',
    this.watermarkSelectMode = 'Select mode',
    this.watermarkLogoModesUnavailableWeb = 'Logo modes are unavailable on web',
    this.watermarkPositionTopLeft = 'Top Left',
    this.watermarkPositionTopRight = 'Top Right',
    this.watermarkPositionBottomLeft = 'Bottom Left',
    this.watermarkPositionBottomRight = 'Bottom Right',
    this.watermarkPositionCenter = 'Center',
    this.watermarkPositionPatternGrid = 'Pattern Grid',
    this.watermarkModeText = 'Text',
    this.watermarkModeLogo = 'Logo',
    this.watermarkModeTextLogo = 'Text + Logo',
  });

  String resolve(String key, String fallback) {
    switch (key) {
      case 'image_editor.back':
        return back;
      case 'image_editor.undo':
        return undo;
      case 'image_editor.redo':
        return redo;
      case 'image_editor.done':
        return done;
      case 'image_editor.apply':
        return apply;
      case 'image_editor.no_image_to_edit':
        return noImageToEdit;
      case 'image_editor.ai_tools_title':
        return aiToolsTitle;
      case 'image_editor.tools.paint':
        return toolPaint;
      case 'image_editor.tools.text':
        return toolText;
      case 'image_editor.tools.watermark':
        return toolWatermark;
      case 'image_editor.tools.vignette':
        return toolVignette;
      case 'image_editor.tools.ai':
        return toolAi;
      case 'image_editor.tools.crop_rotate':
        return toolCropRotate;
      case 'image_editor.tools.tune':
        return toolTune;
      case 'image_editor.tools.filter':
        return toolFilter;
      case 'image_editor.tools.blur':
        return toolBlur;
      case 'image_editor.tools.emoji':
        return toolEmoji;
      case 'image_editor.tune.brilliance':
        return tuneBrilliance;
      case 'image_editor.tune.vibrance':
        return tuneVibrance;
      case 'image_editor.tune.tint':
        return tuneTint;
      case 'image_editor.tune.highlights':
        return tuneHighlights;
      case 'image_editor.tune.shadows':
        return tuneShadows;
      case 'image_editor.ai_editor_title':
        return aiEditorTitle;
      case 'image_editor.ai_tools_unavailable_on_web':
        return aiToolsUnavailableOnWeb;
      case 'image_editor.ai.tools_unavailable_web':
        return aiToolsCurrentlyUnavailableOnWeb;
      case 'image_editor.failed_to_decode_image':
        return failedToDecodeImage;
      case 'image_editor.close':
        return close;
      case 'image_editor.cancel':
        return cancel;
      case 'image_editor.download':
        return download;
      case 'image_editor.downloading':
        return downloading;
      case 'image_editor.skip':
        return skip;
      case 'image_editor.remove':
        return remove;
      case 'image_editor.ai.smart_removal':
        return aiSmartRemoval;
      case 'image_editor.ai.enhance':
        return aiEnhance;
      case 'image_editor.ai.smart_insertion':
        return aiSmartInsertion;
      case 'image_editor.ai.smart_insertion_inpaint':
        return aiSmartInsertionInpaint;
      case 'image_editor.ai.selection_too_small':
        return aiSelectionTooSmall;
      case 'image_editor.ai.lasso_min_points':
        return aiLassoMinPoints;
      case 'image_editor.ai.select_target_shape':
        return aiSelectTargetShape;
      case 'image_editor.ai.shape.rectangle':
        return aiShapeRectangle;
      case 'image_editor.ai.shape.ellipse':
        return aiShapeEllipse;
      case 'image_editor.ai.shape.lasso':
        return aiShapeLasso;
      case 'image_editor.ai.smart':
        return aiSmart;
      case 'image_editor.ai.target':
        return aiTarget;
      case 'image_editor.ai.brush':
        return aiBrush;
      case 'image_editor.ai.eraser':
        return aiEraser;
      case 'image_editor.ai.failed_remove_object':
        return aiFailedRemoveObject;
      case 'image_editor.ai.artifacts_detected_title':
        return aiArtifactsDetectedTitle;
      case 'image_editor.ai.artifacts_detected_body':
        return aiArtifactsDetectedBody;
      case 'image_editor.ai.model_not_found_title':
        return aiModelNotFoundTitle;
      case 'image_editor.ai.model_not_found_body':
        return aiModelNotFoundBody;
      case 'image_editor.ai.download_model_title':
        return aiDownloadModelTitle;
      case 'image_editor.ai.download_model_body':
        return aiDownloadModelBody;
      case 'image_editor.ai.downloading_model_title':
        return aiDownloadingModelTitle;
      case 'image_editor.ai.failed_detect_subject':
        return aiFailedDetectSubject;
      case 'image_editor.watermark.default_text':
        return watermarkDefaultText;
      case 'image_editor.watermark.text_label':
        return watermarkTextLabel;
      case 'image_editor.watermark.pick_logo':
        return watermarkPickLogo;
      case 'image_editor.watermark.remove_logo':
        return watermarkRemoveLogo;
      case 'image_editor.watermark.opacity':
        return watermarkOpacity;
      case 'image_editor.watermark.angle':
        return watermarkAngle;
      case 'image_editor.watermark.size':
        return watermarkSize;
      case 'image_editor.watermark.position_label':
        return watermarkPositionLabel;
      case 'image_editor.watermark.mode_label':
        return watermarkModeLabel;
      case 'image_editor.watermark.select_position':
        return watermarkSelectPosition;
      case 'image_editor.watermark.select_mode':
        return watermarkSelectMode;
      case 'image_editor.watermark.logo_modes_unavailable_web':
        return watermarkLogoModesUnavailableWeb;
      case 'image_editor.watermark.position.top_left':
        return watermarkPositionTopLeft;
      case 'image_editor.watermark.position.top_right':
        return watermarkPositionTopRight;
      case 'image_editor.watermark.position.bottom_left':
        return watermarkPositionBottomLeft;
      case 'image_editor.watermark.position.bottom_right':
        return watermarkPositionBottomRight;
      case 'image_editor.watermark.position.center':
        return watermarkPositionCenter;
      case 'image_editor.watermark.position.pattern_grid':
        return watermarkPositionPatternGrid;
      case 'image_editor.watermark.mode.text':
        return watermarkModeText;
      case 'image_editor.watermark.mode.logo':
        return watermarkModeLogo;
      case 'image_editor.watermark.mode.text_logo':
        return watermarkModeTextLogo;
      default:
        return fallback;
    }
  }
}
