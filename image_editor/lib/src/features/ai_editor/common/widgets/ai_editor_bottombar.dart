import 'package:flutter/material.dart';
import 'package:pro_image_editor/shared/widgets/flat_icon_text_button.dart';

/// Bottom bar for AI tools.
///
/// The background remove tool is wired up; other tools remain placeholders.
class AiEditorBottombar extends StatelessWidget {
  const AiEditorBottombar({
    super.key,
    required this.onBlurBackground,
    required this.onDenoise,
    required this.onObjectRemoval,
    required this.onPeopleRemoval,
    required this.isBusy,
  });

  final VoidCallback? onBlurBackground;
  final VoidCallback? onDenoise;
  final Future<void> Function()? onObjectRemoval;
  final Future<void> Function()? onPeopleRemoval;
  final bool isBusy;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    final items = <_AiToolItem>[
      _AiToolItem(
        label: 'Blur background',
        icon: Icons.blur_on,
        onPressed: isBusy || onBlurBackground == null ? null : onBlurBackground!,
      ),
      _AiToolItem(
        label: 'Denoise',
        icon: Icons.grain,
        onPressed: isBusy || onDenoise == null ? null : onDenoise!,
      ),
      _AiToolItem(
        label: 'Object removal',
        icon: Icons.brush,
        onPressed: isBusy || onObjectRemoval == null
            ? null
            : () {
                onObjectRemoval!();
              },
      ),
      _AiToolItem(
        label: 'People removal',
        icon: Icons.person_off,
        onPressed: isBusy || onPeopleRemoval == null
            ? null
            : () {
                onPeopleRemoval!();
              },
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
                    FlatIconTextButton(
                      label: Text(item.label, style: _bottomTextStyle),
                      icon: Icon(item.icon, size: 22, color: Colors.white),
                      onPressed: item.onPressed,
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

