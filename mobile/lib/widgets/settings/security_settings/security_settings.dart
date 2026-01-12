import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
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

    Future<bool> handleAddBiometric() async {
      if (!localAuthState.canAuthenticate) {
        return false;
      }

      final shouldEnableBiometric = await showDialog<bool>(
        context: context,
        builder: (BuildContext dialogContext) {
          return AlertDialog(
            title: const Text('login_form_add_security_title').tr(),
            content: const Text('login_form_add_security_content').tr(),
            actions: <Widget>[
              TextButton(
                child: const Text('login_form_not_now').tr(),
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              TextButton(child: const Text('common_yes').tr(), onPressed: () => Navigator.of(dialogContext).pop(true)),
            ],
          );
        },
      );

      if (shouldEnableBiometric != true) {
        return false;
      }

      final isAuthenticated = await ref.read(localAuthProvider.notifier).authenticate(context, null);

      return isAuthenticated;
    }

    onEnableBiometricChange(value) async {
      if (!localAuthState.canAuthenticate) {
        if (!context.mounted) return;
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: const Text('security_settings_biometric_not_available').tr()));
        return;
      }
      var shouldEnableBiometric = false;
      if (value == true) {
        shouldEnableBiometric = await handleAddBiometric();
      }
      await Store.put(StoreKey.enableBiometric, shouldEnableBiometric);
      enableBiometric.value = shouldEnableBiometric;
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
