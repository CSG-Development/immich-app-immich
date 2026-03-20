import 'package:flutter/material.dart';
import 'package:image_editor/src/features/ai_editor/common/utils/onnx_model_loader.dart';


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
        title: Text('$modelName model not found'),
        content: Text(
          'The required model was not found at:\n$modelPathOrUrl\n\n'
          'Please provide a valid model asset/path and try again.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('Close'),
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
      title: Text('Download $modelName model?'),
      content: Text(
        'This model is required for $modelName. It will be downloaded and stored on your device. This may use mobile data.',
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(true),
          child: const Text('Download'),
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
      title: Text('Downloading ${widget.modelName} model'),
      content: _error != null
          ? Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _error!,
                  style: theme.textTheme.bodyMedium?.copyWith(
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
                      : 'Downloading…',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
      actions: _error != null
          ? [
              TextButton(
                onPressed: () => Navigator.of(context).pop(false),
                child: const Text('Close'),
              ),
            ]
          : null,
    );
  }
}
