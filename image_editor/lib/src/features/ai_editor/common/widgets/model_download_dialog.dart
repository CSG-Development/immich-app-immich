import 'package:flutter/material.dart';
import 'package:image_editor/src/common/widgets/image_editor_translation_scope.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/onnx_model_loader.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/ai_modal_ui.dart';


/// Shows a dialog asking the user whether to download an AI model.
///
/// Returns `true` if the model is ready to use (cached or downloaded),
/// `false` if the user cancelled.
///
/// [modelPathOrUrl] - asset path or remote URL. If asset or already cached,
/// returns immediately without showing a dialog.
/// [modelName] - display name for the model (e.g. "Background removal").
Future<bool> showModelDownloadDialog(
  BuildContext context, {
  required String? modelPathOrUrl,
  required String modelName,
}) async {
  if (modelPathOrUrl == null || modelPathOrUrl.isEmpty) return false;
  final isRemote = OnnxModelLoader.isRemoteUrl(modelPathOrUrl);
  final localAvailable = await OnnxModelLoader.isLocallyAvailable(modelPathOrUrl);
  if (localAvailable) return true;

  if (!context.mounted) return false;

  if (!isRemote) {
    await showDialog<void>(
      context: context,
      barrierDismissible: true,
      builder: (context) => AlertDialog(
        title: Text(
          ImageEditorTranslationScope.text(
            context,
            'image_editor.ai.model_not_found_title',
            '$modelName model not found',
          ),
        ),
        content: Text(
          ImageEditorTranslationScope.text(
            context,
            'image_editor.ai.model_not_found_body',
            'The required model was not found at:\n$modelPathOrUrl\n\n'
            'Please provide a valid model asset/path and try again.',
          ),
          style: AiModalUi.contentStyle,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: Text(ImageEditorTranslationScope.text(context, 'image_editor.close', 'Close')),
          ),
        ],
      ),
    );
    return false;
  }

  final confirmed = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ModelDownloadDialog(
      modelName: modelName,
      modelUrl: modelPathOrUrl,
    ),
  );

  if (confirmed != true || !context.mounted) return false;

  final result = await showDialog<bool>(
    context: context,
    barrierDismissible: false,
    builder: (context) => _ModelDownloadProgressDialog(
      modelName: modelName,
      modelUrl: modelPathOrUrl,
    ),
  );
  return result == true;
}

class _ModelDownloadDialog extends StatelessWidget {
  const _ModelDownloadDialog({
    required this.modelName,
    required this.modelUrl,
  });

  final String modelName;
  final String modelUrl;

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: Text(
        ImageEditorTranslationScope.text(
          context,
          'image_editor.ai.download_model_title',
          'Download $modelName model?',
        ),
      ),
      content: Text(
        ImageEditorTranslationScope.text(
          context,
          'image_editor.ai.download_model_body',
          'This model is required for $modelName. It will be downloaded and stored on your device. This may use mobile data.',
        ),
        style: AiModalUi.contentStyle,
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(ImageEditorTranslationScope.text(context, 'image_editor.cancel', 'Cancel')),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: Text(ImageEditorTranslationScope.text(context, 'image_editor.download', 'Download')),
        ),
      ],
    );
  }
}

class _ModelDownloadProgressDialog extends StatefulWidget {
  const _ModelDownloadProgressDialog({
    required this.modelName,
    required this.modelUrl,
  });

  final String modelName;
  final String modelUrl;

  @override
  State<_ModelDownloadProgressDialog> createState() =>
      _ModelDownloadProgressDialogState();
}

class _ModelDownloadProgressDialogState extends State<_ModelDownloadProgressDialog> {
  double _progress = 0.0;
  String? _error;

  @override
  void initState() {
    super.initState();
    _download();
  }

  Future<void> _download() async {
    try {
      await OnnxModelLoader.getCachedFilePathWithProgress(
        widget.modelUrl,
        (progress) {
          if (mounted) {
            setState(() => _progress = progress);
          }
        },
      );
      if (mounted) {
        Navigator.of(context).pop(true);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = e.toString());
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: Text(
        ImageEditorTranslationScope.text(
          context,
          'image_editor.ai.downloading_model_title',
          'Downloading ${widget.modelName} model',
        ),
      ),
      content: _error != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _error!,
                  style: (theme.textTheme.bodyMedium ?? AiModalUi.contentStyle).copyWith(
                    color: theme.colorScheme.error,
                  ),
                ),
              ],
            )
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                LinearProgressIndicator(
                  value: _progress >= 0 ? _progress : null,
                ),
                const SizedBox(height: 12),
                Text(
                  _progress >= 0
                      ? '${(_progress * 100).toStringAsFixed(0)}%'
                      : ImageEditorTranslationScope.text(context, 'image_editor.downloading', 'Downloading…'),
                  style: AiModalUi.noteStyle,
                ),
              ],
            ),
      actions: _error != null
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: Text(ImageEditorTranslationScope.text(context, 'image_editor.close', 'Close')),
              ),
            ]
          : null,
    );
  }
}
