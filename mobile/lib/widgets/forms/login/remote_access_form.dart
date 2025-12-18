import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;

import 'package:flutter_svg/svg.dart';
import 'package:homecloud_frontend/providers/hcdevice.provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/local_auth.provider.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/utils/hooks/app_settings_update_hook.dart';
import 'package:immich_mobile/widgets/forms/login/email_input.dart';
import 'package:immich_mobile/widgets/forms/login/login_submit_button.dart';
import 'package:immich_mobile/widgets/forms/login/remote_code_dialog.dart';
import 'package:immich_mobile/providers/remote_access.provider.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';

class RemoteAccessForm extends HookConsumerWidget {
  final VoidCallback switchToCuratorLogin;

  const RemoteAccessForm({super.key, required this.switchToCuratorLogin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emailController = useTextEditingController.fromValue(TextEditingValue.empty);
    final emailFocusNode = useFocusNode();

    final warningMessage = useState<String?>(null);
    final hasEmailError = useState<bool>(false);
    final formKey = useMemoized<GlobalKey<FormState>>(() => GlobalKey<FormState>());

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
              TextButton(
                child: const Text('common_yes').tr(),
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          );
        },
      );

      if (shouldEnableBiometric != true) {
        return false;
      }

      final isAuthenticated =
          await ref.read(localAuthProvider.notifier).authenticate(context, null);

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

    String? validateEmail(String email) {
      final simpleEmailPattern = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
      if (!simpleEmailPattern.hasMatch(email)) {
        return 'login_form_err_invalid_email'.tr();
      }
      return null;
    }

    Future<void> handleNextPress() async {
      final email = emailController.text;

      final isAuthenticated = ref.read(remoteProvider).isAuthenticated;
      final authenticatedEmail = ref.read(deviceProvider).login;

      if (isAuthenticated && authenticatedEmail == email) {
        switchToCuratorLogin();
        return;
      }

      final isDisabled = email.isEmpty || validateEmail(email) != null;
      if (isDisabled) return;
      emailFocusNode.unfocus();

      final remoteAccessService = ref.read(remoteAccessServiceProvider);
      remoteAccessService.initiate(email);
      showRemoteCodeModal(context, () async {
        switchToCuratorLogin();
      }, () => ref.read(remoteAccessServiceProvider).initiate(email));
    }

    useEffect(() {
      emailController.text = ref.read(deviceProvider).login;

      void onFocusChange() {
        debugPrint("emailError: $emailController.text");
        if (emailFocusNode.hasFocus) {
          hasEmailError.value = false;
          warningMessage.value = null;
        } else {
          if (emailController.text.isEmpty) return;
          final emailError = validateEmail(emailController.text);
          if (emailError != null) {
            hasEmailError.value = true;
            warningMessage.value = emailError;
            return;
          }
        }
      }

      emailFocusNode.addListener(onFocusChange);

      return () {
        emailFocusNode.removeListener(onFocusChange);
      };
    }, []);

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Image(width: 140.0, height: 140.0, image: AssetImage('assets/curator-photos-logo.png')),
              SvgPicture.asset(
                context.isDarkTheme ? 'assets/curator-photos-logo-dark.svg' : 'assets/curator-photos-logo-light.svg',
                height: 20.0,
              ),
              const SizedBox(height: 24.0),
              Form(
                key: formKey,
                child: AutofillGroup(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      EmailInput(
                        controller: emailController,
                        focusNode: emailFocusNode,
                        onSubmit: handleNextPress,
                        hasExternalError: hasEmailError.value,
                        validator: (_) => warningMessage.value,
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24.0),
            ],
          ),
        ),
        SwitchListTile.adaptive(
          contentPadding: const EdgeInsets.all(0),
          value: enableBiometric.value,
          onChanged: onEnableBiometricChange,
          activeThumbColor: context.primaryColor,
          title: Text(
            "curator.sign_in_screen_enable_biometric".tr(),
            style: context.textTheme.bodyLarge,
          ),
        ),
        const SizedBox(height: 32.0),
        ValueListenableBuilder(
          valueListenable: emailController,
          builder: (_, value, _) {
            return LoginSubmitButton(
              onPressed: handleNextPress,
              withIcon: false,
              isDisabled: value.text.isEmpty || validateEmail(value.text) != null,
              label: 'next'.tr(),
            );
          },
        ),
      ],
    );
  }
}
