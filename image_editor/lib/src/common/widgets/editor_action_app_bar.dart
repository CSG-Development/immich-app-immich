import 'package:flutter/material.dart';
import 'package:image_editor/src/common/widgets/image_editor_translation_scope.dart';
import 'package:image_editor/src/models/image_editor_translations.dart';
import 'package:image_editor/src/common/utils/platform_tooltip.dart';

/// Reusable editor app bar with back/undo/redo/confirm actions.
class EditorActionAppBar extends StatelessWidget implements PreferredSizeWidget {
  const EditorActionAppBar({
    super.key,
    required this.theme,
    this.title,
    required this.onBack,
    required this.onUndo,
    required this.onRedo,
    required this.onConfirm,
    required this.canUndo,
    required this.canRedo,
    this.isBusy = false,
    this.confirmTooltip,
    this.confirmIcon = Icons.check,
    this.showLeadingBack = false,
    this.confirmEnabled = true,
    this.showUndoRedo = true,
    this.translations = const ImageEditorTranslations(),
  });

  final ThemeData theme;
  final String? title;
  final VoidCallback onBack;
  final VoidCallback onUndo;
  final VoidCallback onRedo;
  final VoidCallback onConfirm;
  final bool canUndo;
  final bool canRedo;
  final bool isBusy;
  final String? confirmTooltip;
  final IconData confirmIcon;
  final bool showLeadingBack;
  final bool confirmEnabled;
  final bool showUndoRedo;
  final ImageEditorTranslations translations;

  @override
  Widget build(BuildContext context) {
    final tr = ImageEditorTranslationScope.of(context);
    final canRunActions = !isBusy;
    final foregroundColor = theme.appBarTheme.foregroundColor ?? Colors.white;
    final disabledColor = foregroundColor.withAlpha(80);

    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: theme.appBarTheme.backgroundColor ?? Colors.black,
      foregroundColor: foregroundColor,
      leading: showLeadingBack
          ? IconButton(
              tooltip: tooltipForPlatform(context, tr.back),
              icon: const Icon(Icons.arrow_back),
              onPressed: canRunActions ? onBack : null,
            )
          : null,
      title: (title?.isEmpty ?? true) ? null : Text(title!),
      actions: [
        if (!showLeadingBack)
          IconButton(
            tooltip: tooltipForPlatform(context, tr.back),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            icon: const Icon(Icons.arrow_back),
            onPressed: canRunActions ? onBack : null,
          ),
        if (!showLeadingBack) const Spacer(),
        if (showUndoRedo)
          IconButton(
            tooltip: tooltipForPlatform(context, tr.undo),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            icon: Icon(Icons.undo, color: canUndo && canRunActions ? foregroundColor : disabledColor),
            onPressed: canUndo && canRunActions ? onUndo : null,
          ),
        if (showUndoRedo)
          IconButton(
            tooltip: tooltipForPlatform(context, tr.redo),
            padding: const EdgeInsets.symmetric(horizontal: 8),
            icon: Icon(Icons.redo, color: canRedo && canRunActions ? foregroundColor : disabledColor),
            onPressed: canRedo && canRunActions ? onRedo : null,
          ),
        IconButton(
          tooltip: tooltipForPlatform(context, confirmTooltip ?? tr.done),
          padding: const EdgeInsets.symmetric(horizontal: 8),
          iconSize: 28,
          icon: Icon(confirmIcon, color: canRunActions && confirmEnabled ? foregroundColor : disabledColor),
          onPressed: canRunActions && confirmEnabled ? onConfirm : null,
        ),
      ],
    );
  }

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
