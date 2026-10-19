import 'package:flutter/material.dart';

import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/theme/theme_data.dart';

class MapSettingsListTile extends StatelessWidget {
  final String title;
  final bool selected;
  final Function(bool) onChanged;

  const MapSettingsListTile({super.key, required this.title, required this.selected, required this.onChanged});

  @override
  Widget build(BuildContext context) {
    return SwitchListTile.adaptive(
      activeThumbColor: resolveSwitchActiveThumbColor(context),
      title: Text(title, style: context.textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w500, height: 1.5)),
      value: selected,
      onChanged: onChanged,
    );
  }
}
