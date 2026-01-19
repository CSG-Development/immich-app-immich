import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;

import 'package:flutter_svg/svg.dart';
import 'package:homecloud_frontend/providers/hcdevice.provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/widgets/forms/login/email_input.dart';
import 'package:immich_mobile/widgets/forms/login/login_submit_button.dart';

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

    String? validateEmail(String email) {
      final simpleEmailPattern = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
      if (!simpleEmailPattern.hasMatch(email)) {
        return 'login_form_err_invalid_email'.tr();
      }
      return null;
    }

    Future<void> handleNextPress() async {
      emailFocusNode.unfocus();
      final email = emailController.text;

      final isDisabled = email.isEmpty || validateEmail(email) != null;
      if (isDisabled) return;

      final isAuthenticated = ref.read(remoteProvider).isAuthenticated;
      final authenticatedEmail = ref.read(deviceProvider).login;

      if (isAuthenticated && authenticatedEmail == email) {
        switchToCuratorLogin();
        return;
      }

      if (authenticatedEmail != email) {
        ref.read(remoteProvider).logout();
      }

      ref.read(deviceProvider).setHost(login: email);
      switchToCuratorLogin();
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
        ValueListenableBuilder(
          valueListenable: emailController,
          builder: (_, value, _) {
            return LoginSubmitButton(
              onPressed: handleNextPress,
              withIcon: false,
              isDisabled: value.text.isEmpty || validateEmail(value.text) != null || hasEmailError.value,
              label: 'next'.tr(),
            );
          },
        ),
      ],
    );
  }
}
