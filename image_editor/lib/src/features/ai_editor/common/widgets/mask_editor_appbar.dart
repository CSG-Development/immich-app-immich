import 'package:flutter/material.dart';

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
    final theme = Theme.of(context);

    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: theme.appBarTheme.backgroundColor ?? Colors.black,
      foregroundColor: theme.appBarTheme.foregroundColor ?? Colors.white,
      leading: IconButton(
        tooltip: 'Back',
        icon: const Icon(Icons.arrow_back),
        onPressed: onCancel,
      ),
      title: (title?.isEmpty ?? true) ? null : Text(title!),
      actions: [
        IconButton(
          tooltip: 'Undo',
          padding: const EdgeInsets.symmetric(horizontal: 8),
          icon: Icon(
            Icons.undo,
            color: canUndo ? Colors.white : Colors.white.withAlpha(80),
          ),
          onPressed: canUndo ? onUndo : null,
        ),
        IconButton(
          tooltip: 'Redo',
          padding: const EdgeInsets.symmetric(horizontal: 8),
          icon: Icon(
            Icons.redo,
            color: canRedo ? Colors.white : Colors.white.withAlpha(80),
          ),
          onPressed: canRedo ? onRedo : null,
        ),
        IconButton(
          tooltip: 'Apply',
          padding: const EdgeInsets.symmetric(horizontal: 8),
          iconSize: 28,
          icon: Icon(
            Icons.check,
            color: applyEnabled ? Colors.white : Colors.white.withAlpha(80),
          ),
          onPressed: applyEnabled ? onApply : null,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
