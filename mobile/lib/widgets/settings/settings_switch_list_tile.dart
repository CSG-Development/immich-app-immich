import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/theme/theme_data.dart';

class SettingsSwitchListTile extends StatelessWidget {
  final ValueNotifier<bool> valueNotifier;
  final String title;
  final bool enabled;
  final String? subtitle;
  final IconData? icon;
  final Function(bool)? onChanged;
  final EdgeInsets? contentPadding;
  final TextStyle? titleStyle;
  final TextStyle? subtitleStyle;

  const SettingsSwitchListTile({
    required this.valueNotifier,
    required this.title,
    this.subtitle,
    this.icon,
    this.enabled = true,
    this.onChanged,
    this.contentPadding = const EdgeInsets.symmetric(horizontal: 20),
    this.titleStyle,
    this.subtitleStyle,
    super.key,
  });

  @override
  Widget build(BuildContext context) {
    void onSwitchChanged(bool value) {
      if (!enabled) {
        return;
      }

      valueNotifier.value = value;
      onChanged?.call(value);
    }

    final titleWidget = Text(
      title,
      style:
          titleStyle ??
          context.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
            color: enabled ? null : context.themeData.disabledColor,
            height: 1.5,
          ),
    );
    final subtitleWidget = subtitle != null
        ? Text(
            subtitle!,
            style:
                subtitleStyle ??
                context.textTheme.bodyMedium?.copyWith(
                  color: enabled ? context.colorScheme.onSurfaceSecondary : context.themeData.disabledColor,
                ),
          )
        : null;
    final secondary = icon != null ? Icon(icon!, color: valueNotifier.value ? context.primaryColor : null) : null;

    // Material under SG so SwitchTheme track outline applies on iOS (Cupertino adaptive ignores it).
    if (isSgTheme(context.themeData)) {
      return SwitchListTile(
        contentPadding: contentPadding,
        selectedTileColor: enabled ? null : context.themeData.disabledColor,
        value: valueNotifier.value,
        onChanged: enabled ? onSwitchChanged : null,
        dense: true,
        secondary: secondary,
        title: titleWidget,
        subtitle: subtitleWidget,
      );
    }

    return SwitchListTile.adaptive(
      contentPadding: contentPadding,
      selectedTileColor: enabled ? null : context.themeData.disabledColor,
      value: valueNotifier.value,
      onChanged: onSwitchChanged,
      activeThumbColor: resolveSwitchActiveThumbColor(context, enabled: enabled),
      dense: true,
      secondary: secondary,
      title: titleWidget,
      subtitle: subtitleWidget,
    );
  }
}
