import 'package:flutter/material.dart';
import 'package:image_editor/src/common/widgets/editor_action_app_bar.dart';

/// App bar for mask-editor overlays (people/object/animal removal), with
/// back/done as icons and undo/redo in the bar, matching the AI editor screen.
class MaskEditorAppBar extends StatelessWidget implements PreferredSizeWidget {
  const MaskEditorAppBar({
    super.key,
    this.title,
    required this.onCancel,
    required this.onApply,
    required this.applyEnabled,
    required this.canUndo,
    required this.canRedo,
    required this.onUndo,
    required this.onRedo,
  });

  final String? title;
  final VoidCallback onCancel;
  final VoidCallback onApply;
  final bool applyEnabled;
  final bool canUndo;
  final bool canRedo;
  final VoidCallback onUndo;
  final VoidCallback onRedo;

  @override
  Widget build(BuildContext context) {
    return EditorActionAppBar(
      theme: Theme.of(context),
      title: title,
      showLeadingBack: true,
      onBack: onCancel,
      onUndo: onUndo,
      onRedo: onRedo,
      onConfirm: onApply,
      canUndo: canUndo,
      canRedo: canRedo,
      confirmEnabled: applyEnabled,
      confirmTooltip: 'Apply',
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
