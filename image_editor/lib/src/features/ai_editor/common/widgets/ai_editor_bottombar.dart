import 'package:flutter/material.dart';
import 'package:pro_image_editor/shared/widgets/flat_icon_text_button.dart';

/// Bottom bar for AI tools.
///
/// The background remove tool is wired up; other tools remain placeholders.
class AiEditorBottomBar extends StatelessWidget {
  const AiEditorBottomBar({
    super.key,
    required this.onObjectRemoval,
    required this.onEnhance,
    this.onSmartInsertion,
    required this.isBusy,
  });

  final Future<void> Function()? onObjectRemoval;
  final Future<void> Function()? onEnhance;
  final VoidCallback? onSmartInsertion;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final items = <_AiToolItem>[
      _AiToolItem(
        label: 'Smart removal',
        icon: Icons.healing,
        onPressed: isBusy || onObjectRemoval == null
            ? null
            : () {
                onObjectRemoval!();
              },
      ),
      _AiToolItem(
        label: 'Enhance',
        icon: Icons.auto_fix_high,
        onPressed: isBusy || onEnhance == null
            ? null
            : () {
                onEnhance!();
              },
      ),
      _AiToolItem(
        label: 'Smart insertion',
        icon: Icons.add_photo_alternate_outlined,
        onPressed: isBusy || onSmartInsertion == null ? null : onSmartInsertion,
      ),
    ];

    return Scrollbar(
      thumbVisibility: false,
      trackVisibility: false,
      thickness: 0.0,
      child: BottomAppBar(
        height: kBottomNavigationBarHeight,
        color: theme.bottomAppBarTheme.color ?? Colors.black,
        padding: EdgeInsets.zero,
        child: Center(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  for (final item in items)
                    Tooltip(
                      message: item.label,
                      child: Semantics(
                        button: true,
                        label: item.label,
                        child: FlatIconTextButton(
                          label: Text(item.label, style: _bottomTextStyle),
                          icon: Icon(item.icon, size: 22, color: Colors.white),
                          onPressed: item.onPressed,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  static const _bottomTextStyle = TextStyle(fontSize: 10.0, color: Colors.white);
}

typedef AiEditorBottombar = AiEditorBottomBar;

class _AiToolItem {
  final String label;
  final IconData icon;
  final VoidCallback? onPressed;

  const _AiToolItem({
    required this.label,
    required this.icon,
    required this.onPressed,
  });
}

