import 'package:flutter/material.dart';
import 'package:image_editor/src/common/widgets/editor_action_app_bar.dart';

/// App bar for the vignette editor, with undo/redo and done/close actions.
class VignetteEditorAppBar extends StatelessWidget implements PreferredSizeWidget {
  const VignetteEditorAppBar({
    super.key,
    required this.theme,
    required this.canRedo,
    required this.canUndo,
    required this.onRedo,
    required this.onUndo,
    required this.onClose,
    required this.onDone,
  });

  final ThemeData theme;

  final bool canRedo;

  final bool canUndo;

  final VoidCallback onRedo;
  final VoidCallback onUndo;
  final VoidCallback onClose;
  final VoidCallback onDone;

  @override
  Widget build(BuildContext context) {
    return EditorActionAppBar(
      theme: theme,
      onBack: onClose,
      onUndo: onUndo,
      onRedo: onRedo,
      onConfirm: onDone,
      canUndo: canUndo,
      canRedo: canRedo,
      confirmTooltip: 'Done',
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

typedef VignetteEditorAppbar = VignetteEditorAppBar;
