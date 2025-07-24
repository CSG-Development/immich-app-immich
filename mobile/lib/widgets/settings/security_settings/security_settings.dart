import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/local_auth.provider.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/utils/hooks/app_settings_update_hook.dart';
import 'package:immich_mobile/widgets/settings/settings_sub_page_scaffold.dart';
import 'package:immich_mobile/widgets/settings/settings_switch_list_tile.dart';

class SecuritySettings extends HookConsumerWidget {
  const SecuritySettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localAuthState = ref.watch(localAuthProvider);
    final enableBiometric = useAppSettingsState(AppSettingsEnum.enableBiometric);

    onEnableBiometricChange(value) async {
      if (value) {
        if (!localAuthState.canAuthenticate) {
          if (!context.mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('security_settings_biometric_not_available').tr(),
            ),
          );
          return;
        }
      }
      enableBiometric.value = value;
    }

    final securitySettings = [
      SettingsSwitchListTile(
        valueNotifier: enableBiometric,
        title: 'biometric_switch'.tr(),
        subtitle: 'biometric_subtitle'.tr(),
        onChanged: onEnableBiometricChange,
      ),
    ];

    return SettingsSubPageScaffold(settings: securitySettings);
  }
}
