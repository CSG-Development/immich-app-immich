import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/providers/local_auth.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/services/secure_storage.service.dart';
import 'package:immich_mobile/utils/hooks/add_biometric_auth_hook.dart';
import 'package:immich_mobile/utils/hooks/app_settings_update_hook.dart';
import 'package:immich_mobile/widgets/settings/settings_radio_list_tile.dart';
import 'package:immich_mobile/widgets/settings/settings_sub_page_scaffold.dart';
import 'package:immich_mobile/widgets/settings/settings_switch_list_tile.dart';
import 'package:immich_mobile/pages/security/lock_flow.dart';

class SecuritySettings extends HookConsumerWidget {
  const SecuritySettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localAuthState = ref.watch(localAuthProvider);
    final enableBiometric = useAppSettingsState(AppSettingsEnum.enableBiometric);
    final appLockTimeoutIndex = useAppSettingsState(AppSettingsEnum.appLockTimeoutIndex);
    final appLockTimeout = AppLockTimeout.values[appLockTimeoutIndex.value];

    final secureStorage = ref.watch(secureStorageServiceProvider);
    final enablePasscodeLock = useState(false);
    final enablePatternLock = useState(false);

    useEffect(() {
      Future<void>(() async {
        final passcode = await secureStorage.read(kSecuredPasscode);
        final pattern = await secureStorage.read(kSecuredPattern);
        enablePasscodeLock.value = passcode != null;
        enablePatternLock.value = pattern != null;
      });
      return null;
    }, const []);

    final handleAddBiometric = useAddBiometricAuthHook(context, ref);

    onEnableBiometricLockChange(value) async {
      if (!localAuthState.canAuthenticate) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: const Text('security_settings_biometric_not_available').tr()));
        return;
      }
      var shouldEnableBiometric = false;
      if (value == true) {
        shouldEnableBiometric = await handleAddBiometric();
      }

      enableBiometric.value = shouldEnableBiometric;
    }

    onEnablePasscodeLockChange(value) async {
      final result = await context.pushRoute(
        PasscodeLockRoute(flow: value == true ? LockFlow.create : LockFlow.remove),
      );

      if (result == true) {
        enablePasscodeLock.value = value;
        if (!value && !enablePatternLock.value) {
          enableBiometric.value = false;
        } else {
          await Future.delayed(const Duration(milliseconds: 100), () {
            final enableBiometricUpdate = Store.get(StoreKey.enableBiometric);
            if (enableBiometricUpdate == true) {
              enableBiometric.value = true;
            }
          });
        }
      } else {
        enablePasscodeLock.value = !value;
      }
    }

    onEnablePatternLockChange(value) async {
      final result = await context.pushRoute(PatternLockRoute(flow: value == true ? LockFlow.create : LockFlow.remove));

      if (result == true) {
        enablePatternLock.value = value;
        if (!value && !enablePasscodeLock.value) {
          enableBiometric.value = false;
        } else {
          await Future.delayed(const Duration(milliseconds: 100), () {
            final enableBiometricUpdate = Store.get(StoreKey.enableBiometric);
            if (enableBiometricUpdate == true) {
              enableBiometric.value = true;
            }
          });
        }
      } else {
        enablePatternLock.value = !value;
      }
    }

    Future<String?> showLockApplicationDialog() {
      return showDialog<String>(
        context: context,
        builder: (context) => AlertDialog(
          titlePadding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 0),
          contentPadding: const EdgeInsets.fromLTRB(4.0, 16.0, 4.0, 24.0),
          title: Text('curator.settings_lock_application'.tr()),
          content: IntrinsicHeight(
            child: SettingsRadioListTile(
              controlAffinity: ListTileControlAffinity.leading,
              groups: [
                SettingsRadioGroup(title: AppLockTimeout.immediately.tr(), value: AppLockTimeout.immediately),
                SettingsRadioGroup(title: AppLockTimeout.m1.tr(), value: AppLockTimeout.m1),
                SettingsRadioGroup(title: AppLockTimeout.m5.tr(), value: AppLockTimeout.m5),
                SettingsRadioGroup(title: AppLockTimeout.m30.tr(), value: AppLockTimeout.m30),
              ],
              groupBy: appLockTimeout,
              onRadioChanged: (AppLockTimeout? value) {
                if (value != null) {
                  appLockTimeoutIndex.value = value.index;
                }
                context.pop();
              },
            ),
          ),
        ),
      );
    }

    final lockApplicationAvailable = enablePasscodeLock.value || enablePatternLock.value || enableBiometric.value;
    final biometricAvailable = enablePasscodeLock.value || enablePatternLock.value || enableBiometric.value;

    final securitySettings = [
      SettingsSwitchListTile(
        valueNotifier: enablePasscodeLock,
        title: 'curator.settings_passcode_lock'.tr(),
        onChanged: onEnablePasscodeLockChange,
      ),
      SettingsSwitchListTile(
        valueNotifier: enablePatternLock,
        title: 'curator.settings_pattern_lock'.tr(),
        onChanged: onEnablePatternLockChange,
      ),
      SettingsSwitchListTile(
        valueNotifier: enableBiometric,
        title: 'curator.settings_biometric_lock'.tr(),
        subtitle: 'curator.settings_biometric_lock_description'.tr(),
        onChanged: onEnableBiometricLockChange,
        enabled: biometricAvailable,
      ),
      ListTile(
        enabled: lockApplicationAvailable,
        contentPadding: const EdgeInsets.symmetric(horizontal: 20),
        dense: true,
        title: Text(
          "curator.settings_lock_application".tr(),
          style: context.textTheme.bodyLarge?.copyWith(
            fontWeight: FontWeight.w500,
            color: lockApplicationAvailable
                ? context.colorScheme.onSurface
                : context.colorScheme.onSurface.withAlpha(120),
          ),
        ),
        subtitle: Text(
          appLockTimeout.tr(),
          style: context.textTheme.bodyMedium?.copyWith(
            color: lockApplicationAvailable
                ? context.colorScheme.onSurfaceSecondary
                : context.colorScheme.onSurfaceSecondary.withAlpha(140),
          ),
        ),
        onTap: () => showLockApplicationDialog(),
      ),
    ];

    return SettingsSubPageScaffold(settings: securitySettings);
  }
}
