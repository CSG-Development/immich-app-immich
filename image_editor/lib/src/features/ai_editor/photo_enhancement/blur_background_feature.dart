import 'package:flutter/material.dart';
import 'package:image_editor/src/common/widgets/image_editor_translation_scope.dart';
import 'package:image_editor/src/features/ai_editor/common/widgets/ai_modal_ui.dart';

enum BlurBackgroundMode { automatic, manual }

/// Modal that asks user how to apply blur background.
class BlurBackgroundFeature extends StatelessWidget {
  const BlurBackgroundFeature({super.key});

  static Future<BlurBackgroundMode?> show({
    required BuildContext context,
  }) {
    return showDialog<BlurBackgroundMode>(
      context: context,
      useRootNavigator: false,
      builder: (ctx) => const BlurBackgroundFeature(),
    );
  }

  String _t(BuildContext context, String key, String fallback) =>
      ImageEditorTranslationScope.text(context, key, fallback);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AiModalUi.radius),
      ),
      title: Text(
        _t(context, 'image_editor.ai.blur_background', 'Blur background'),
        style: theme.textTheme.titleLarge,
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            _t(context, 'image_editor.ai.blur_background_prompt', 'Choose how to apply blur background.'),
            style: AiModalUi.contentStyle,
          ),
          const SizedBox(height: AiModalUi.itemSpacing),
          Text(
            _t(
              context,
              'image_editor.ai.blur_background_auto_manual_note',
              'Automatic: detect subject and blur background.\nManual: paint the area to keep sharp.',
            ),
            style: AiModalUi.noteStyle,
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () {
            Navigator.of(context).pop(null);
          },
          child: Text(_t(context, 'image_editor.cancel', 'Cancel')),
        ),
        TextButton.icon(
          onPressed: () => Navigator.of(context).pop(BlurBackgroundMode.manual),
          icon: const Icon(Icons.brush, size: 18),
          label: Text(_t(context, 'image_editor.ai.manual', 'Manual')),
        ),
        FilledButton.icon(
          onPressed: () => Navigator.of(context).pop(BlurBackgroundMode.automatic),
          icon: const Icon(Icons.auto_awesome, size: 18),
          label: Text(_t(context, 'image_editor.ai.automatic', 'Automatic')),
        ),
      ],
    );
  }
}