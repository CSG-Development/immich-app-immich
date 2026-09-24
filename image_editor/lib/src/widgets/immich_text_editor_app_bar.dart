import 'package:flutter/material.dart';
import 'package:pro_image_editor/pro_image_editor.dart';

/// Text editor app bar with a background-mode control that changes visually
/// when toggled (icon + primary tint).
class ImmichTextEditorAppBar extends StatelessWidget implements PreferredSizeWidget {
  const ImmichTextEditorAppBar({
    super.key,
    required this.textEditorConfigs,
    required this.i18n,
    required this.onClose,
    required this.onDone,
    required this.align,
    required this.onToggleTextAlign,
    required this.onOpenFontScaleBottomSheet,
    required this.onToggleBackgroundMode,
    required this.backgroundMode,
    required this.constraints,
    required this.activeColor,
  });

  final TextEditorConfigs textEditorConfigs;
  final I18nTextEditor i18n;
  final TextAlign align;
  final BoxConstraints constraints;
  final Color activeColor;
  final LayerBackgroundMode backgroundMode;
  final VoidCallback onClose;
  final VoidCallback onDone;
  final VoidCallback onToggleTextAlign;
  final VoidCallback onOpenFontScaleBottomSheet;
  final VoidCallback onToggleBackgroundMode;

  static IconData iconForBackgroundMode(LayerBackgroundMode mode) {
    switch (mode) {
      case LayerBackgroundMode.onlyColor:
        return Icons.format_color_text_rounded;
      case LayerBackgroundMode.backgroundAndColor:
        return Icons.format_color_fill_rounded;
      case LayerBackgroundMode.background:
        return Icons.layers_rounded;
      case LayerBackgroundMode.backgroundAndColorWithOpacity:
        return Icons.opacity_rounded;
    }
  }

  bool get _isBackgroundActive => backgroundMode != LayerBackgroundMode.onlyColor;

  @override
  Widget build(BuildContext context) {
    const int defaultIconButtonSize = 48;
    final configButtons = _getConfigButtons();
    final iconButtonsSize = (2 + configButtons.length) * defaultIconButtonSize;

    return AppBar(
      automaticallyImplyLeading: false,
      backgroundColor: textEditorConfigs.style.appBarBackground,
      foregroundColor: textEditorConfigs.style.appBarColor,
      actions: [
        IconButton(
          tooltip: i18n.back,
          padding: const EdgeInsets.symmetric(horizontal: 8),
          icon: Icon(textEditorConfigs.icons.backButton),
          onPressed: onClose,
        ),
        const Spacer(),
        if (constraints.maxWidth >= iconButtonsSize) ...[
          ...configButtons,
          const Spacer(),
          _buildDoneBtn(),
        ] else ...[
          _buildDoneBtn(),
          PopupMenuButton<String>(
            tooltip: i18n.smallScreenMoreTooltip,
            onSelected: (value) {
              switch (value) {
                case 'align':
                  onToggleTextAlign();
                case 'scale':
                  onOpenFontScaleBottomSheet();
                case 'background':
                  onToggleBackgroundMode();
              }
            },
            itemBuilder: (context) => [
              if (textEditorConfigs.showTextAlignButton)
                PopupMenuItem(
                  value: 'align',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      align == TextAlign.left
                          ? textEditorConfigs.icons.alignLeft
                          : align == TextAlign.right
                              ? textEditorConfigs.icons.alignRight
                              : textEditorConfigs.icons.alignCenter,
                    ),
                    title: Text(i18n.textAlign),
                  ),
                ),
              if (textEditorConfigs.showFontScaleButton)
                PopupMenuItem(
                  value: 'scale',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(textEditorConfigs.icons.fontScale),
                    title: Text(i18n.fontScale),
                  ),
                ),
              if (textEditorConfigs.showBackgroundModeButton)
                PopupMenuItem(
                  value: 'background',
                  child: ListTile(
                    contentPadding: EdgeInsets.zero,
                    leading: Icon(
                      iconForBackgroundMode(backgroundMode),
                      color: _isBackgroundActive ? activeColor : null,
                    ),
                    title: Text(i18n.backgroundMode),
                  ),
                ),
            ],
          ),
        ],
      ],
    );
  }

  Widget _buildDoneBtn() {
    return IconButton(
      key: const ValueKey('TextEditorDoneButton'),
      tooltip: i18n.done,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      icon: Icon(textEditorConfigs.icons.applyChanges),
      iconSize: 28,
      onPressed: onDone,
    );
  }

  List<IconButton> _getConfigButtons() => [
        if (textEditorConfigs.showTextAlignButton)
          IconButton(
            key: const ValueKey('TextAlignIconButton'),
            tooltip: i18n.textAlign,
            onPressed: onToggleTextAlign,
            icon: Icon(
              align == TextAlign.left
                  ? textEditorConfigs.icons.alignLeft
                  : align == TextAlign.right
                      ? textEditorConfigs.icons.alignRight
                      : textEditorConfigs.icons.alignCenter,
            ),
          ),
        if (textEditorConfigs.showFontScaleButton)
          IconButton(
            key: const ValueKey('BackgroundModeFontScaleButton'),
            tooltip: i18n.fontScale,
            onPressed: onOpenFontScaleBottomSheet,
            icon: Icon(textEditorConfigs.icons.fontScale),
          ),
        if (textEditorConfigs.showBackgroundModeButton)
          IconButton(
            key: const ValueKey('BackgroundModeColorIconButton'),
            tooltip: i18n.backgroundMode,
            onPressed: onToggleBackgroundMode,
            color: _isBackgroundActive ? activeColor : null,
            icon: Icon(iconForBackgroundMode(backgroundMode)),
          ),
      ];

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);
}
