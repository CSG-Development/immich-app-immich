import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/base_action_button.widget.dart';
import 'package:immich_mobile/providers/airplay.provider.dart';
import 'package:immich_mobile/services/airplay.service.dart';

class AirplayActionButton extends ConsumerWidget {
  const AirplayActionButton({super.key, this.iconOnly = false, this.menuItem = false});

  final bool iconOnly;
  final bool menuItem;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAirPlayConnected = ref.watch(airplayProvider);

    return BaseActionButton(
      iconData: Icons.airplay,
      iconColor: isAirPlayConnected ? context.primaryColor : null,
      label: "airplay".t(context: context),
      onPressed: () async {
        await AirplayService.showAirPlayMenu();
      },
      iconOnly: iconOnly,
      menuItem: menuItem,
    );
  }
}
