import 'package:device_info_plus/device_info_plus.dart' show DeviceInfoPlugin;
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/widgets/forms/login/email_input.dart';
import 'package:immich_mobile/widgets/forms/login/login_button.dart';
import 'package:immich_mobile/widgets/forms/login/remote_code_dialog.dart';
import 'package:logging/logging.dart';

import 'package:homecloud_frontend/homecloud_frontend.dart';
import 'package:homecloud_frontend/api/remote_access.swagger.dart';

class RemoteAccessForm extends HookConsumerWidget {
  final log = Logger('RemoteAccessForm');
  final VoidCallback switchToCuratorLogin;

  RemoteAccessForm({super.key, required this.switchToCuratorLogin});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emailController = useTextEditingController.fromValue(TextEditingValue.empty);
    final emailFocusNode = useFocusNode();

    final warningMessage = useState<String?>(null);
    final hasEmailError = useState<bool>(false);
    final formKey = useMemoized<GlobalKey<FormState>>(() => GlobalKey<FormState>());

    String clientFriendlyName = '';

    String? validateEmail(String email) {
      final simpleEmailPattern = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
      if (!simpleEmailPattern.hasMatch(email)) {
        return 'login_form_err_invalid_email'.tr();
      }
      return null;
    }

    /// Handle API errors by printing them in debug mode
    void handleError(ApiErrorMessage message, dynamic error) {
      log.severe("[SignInScreen] $message: ${extractErrorMessage(error)}");
    }

    Future<String> getClientFriendlyName() async {
      if (clientFriendlyName.isNotEmpty) {
        return clientFriendlyName;
      }
      final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
      String name = "Curator Photos";
      Map<String, dynamic>? data;
      try {
        if (defaultTargetPlatform == TargetPlatform.android) {
          final androidInfo = await deviceInfoPlugin.androidInfo;
          data = androidInfo.data;
          // The name of the device (Customizable by the user)
          name = androidInfo.name;
          if (name.isEmpty) {
            // The consumer-visible brand with which the product/hardware will be associated, if any.
            name = androidInfo.brand;
            if (name.isEmpty) {
              // The manufacturer of the product/hardware.
              name = androidInfo.manufacturer;
            }
            // + The end-user-visible name for the end product.
            name = "$name ${androidInfo.model}";
          }
        } else if (defaultTargetPlatform == TargetPlatform.iOS) {
          final iosInfo = await deviceInfoPlugin.iosInfo;
          data = iosInfo.data;
          // Commercial or user-known model name Examples: iPhone 16 Pro, iPad Pro 11-Inch 3
          name = iosInfo.modelName;
        }
      } catch (_) {}
      if (kDebugMode) {
        debugPrint("ClientFriendlyName : $name");
        if (data != null) {
          data.forEach((key, value) {
            debugPrint("[DeviceInfoPlugin] $key: $value");
          });
        }
      }
      return name;
    }

    /// Initiate remote access authentication by sending a code to the given email
    Future<void> initiateRemoteAccess() async {
      final email = emailController.text;

      emailFocusNode.unfocus();

      if (email.isEmpty) return;

      final emailError = validateEmail(email);
      if (emailError != null) {
        hasEmailError.value = true;
        warningMessage.value = emailError;
        return;
      }

      try {
        clientFriendlyName = await getClientFriendlyName();
        final response = await ref
            .read(remoteProvider)
            .api
            .clientV1AuthInitiatePost(
              type: ClientV1AuthInitiatePostType.email,
              body: Code$RequestBody(
                email: email,
                clientId: ref.read(remoteProvider).clientId,
                clientFriendlyName: clientFriendlyName,
              ),
            );
        // 	Success: A reference is returned and the user will receive a code to continue authenticating.
        if (response.isSuccessful && context.mounted) {
          // Save email in device provider to pre-fill next time
          ref.read(deviceProvider.notifier).setHost(login: email);
          // Clear any previous authentication of remote access server
          ref.read(remoteProvider.notifier).logout();
          if (kDebugMode) {
            debugPrint("[SignInScreen] Remote access initiated for email: $email, response: ${response.body}");
          }
          ref.read(remoteProvider.notifier).reference = response.body?.reference;

          return;
        } else {
          handleError(ApiErrorMessage.remoteApi, response);
          return;
        }
      } catch (error) {
        handleError(ApiErrorMessage.remoteApi, error);
        return;
      }
    }

    Future<void> handleNextPress() async {
      initiateRemoteAccess();
      showRemoteCodeModal(
        context,
        () async {
          switchToCuratorLogin();
        },
        handleError,
        initiateRemoteAccess,
      );
    }

    useEffect(() {
      emailController.text = ref.read(deviceProvider).login;

      void onFocusChange() {
        if (emailFocusNode.hasFocus) {
          hasEmailError.value = false;
          warningMessage.value = null;
        }
      }

      emailFocusNode.addListener(onFocusChange);

      return () {
        try {
          emailFocusNode.removeListener(onFocusChange);
          emailController.dispose();
          emailFocusNode.dispose();
          warningMessage.dispose();
          hasEmailError.dispose();
        } catch (e) {
          // Ignore
        }
      };
    }, []);

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Image(width: 140.0, height: 140.0, image: AssetImage('assets/curator-photos-logo.png')),
        SvgPicture.asset(
          context.isDarkTheme ? 'assets/curator-photos-logo-dark.svg' : 'assets/curator-photos-logo-light.svg',
          height: 40.0,
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
        LoginButton(onPressed: handleNextPress, withIcon: false, isDisabled: hasEmailError.value),
      ],
    );
  }
}
