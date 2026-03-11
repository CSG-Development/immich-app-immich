import 'package:flutter/material.dart';

/// App bar for the AI editor, with undo/redo and done/close actions.
class AiEditorAppbar extends StatelessWidget implements PreferredSizeWidget {
  const AiEditorAppbar({
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
    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: theme.appBarTheme.backgroundColor ?? Colors.black,
      foregroundColor: theme.appBarTheme.foregroundColor ?? Colors.white,
      title: const Text('AI Tools'),
      actions: [
        IconButton(
          tooltip: 'Back',
          padding: const EdgeInsets.symmetric(horizontal: 8),
          icon: const Icon(Icons.arrow_back),
          onPressed: onClose,
        ),
        const Spacer(),
        IconButton(
          tooltip: 'Undo',
          padding: const EdgeInsets.symmetric(horizontal: 8),
          icon: Icon(Icons.undo, color: canUndo ? Colors.white : Colors.white.withAlpha(80)),
          onPressed: canUndo ? onUndo : null,
        ),
        IconButton(
          tooltip: 'Redo',
          padding: const EdgeInsets.symmetric(horizontal: 8),
          icon: Icon(Icons.redo, color: canRedo ? Colors.white : Colors.white.withAlpha(80)),
          onPressed: canRedo ? onRedo : null,
        ),
        IconButton(
          tooltip: 'Done',
          padding: const EdgeInsets.symmetric(horizontal: 8),
          icon: const Icon(Icons.check),
          iconSize: 28,
          onPressed: onDone,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}

