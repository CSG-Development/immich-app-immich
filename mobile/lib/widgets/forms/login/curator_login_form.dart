import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/local_auth.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/provider_utils.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:immich_mobile/utils/version_compatibility.dart';
import 'package:immich_mobile/widgets/forms/login/email_input.dart';
import 'package:immich_mobile/widgets/forms/login/loading_icon.dart';
import 'package:immich_mobile/widgets/forms/login/login_button.dart';
import 'package:immich_mobile/widgets/forms/login/password_input.dart';
import 'package:immich_mobile/widgets/forms/login/server_endpoint_input.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';

class CuratorLoginForm extends HookConsumerWidget {
  CuratorLoginForm({super.key});

  final log = Logger('LoginForm');

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emailController =
        useTextEditingController.fromValue(TextEditingValue.empty);
    final passwordController =
        useTextEditingController.fromValue(TextEditingValue.empty);
    final serverEndpointController =
        useTextEditingController.fromValue(TextEditingValue.empty);

    final emailFocusNode = useFocusNode();
    final passwordFocusNode = useFocusNode();
    final serverEndpointFocusNode = useFocusNode();

    final isLoading = useState<bool>(false);
    final isLoadingServer = useState<bool>(false);
    final warningMessage = useState<String?>(null);
    final hasEmailError = useState<bool>(false);
    final hasPasswordError = useState<bool>(false);
    final isFormValid = useState<bool>(false);

    final loginFormKey = GlobalKey<FormState>();

    final serverEndpoint = useState<String?>(null);
    final serverInfo = ref.watch(serverInfoProvider);
    final localAuthState = ref.watch(localAuthProvider);

    // Track form validity
    useEffect(
      () {
        void checkFormValidity() {
          final isValid = emailController.text.isNotEmpty &&
              passwordController.text.isNotEmpty &&
              serverEndpointController.text.isNotEmpty;
          isFormValid.value = isValid;
        }

        emailController.addListener(checkFormValidity);
        passwordController.addListener(checkFormValidity);
        serverEndpointController.addListener(checkFormValidity);

        return () {
          emailController.removeListener(checkFormValidity);
          passwordController.removeListener(checkFormValidity);
          serverEndpointController.removeListener(checkFormValidity);
        };
      },
      [],
    );

    // Clear warning and errors when inputs change
    useEffect(
      () {
        void listener() {
          if (warningMessage.value != null) {
            warningMessage.value = null;
          }
          if (hasEmailError.value) {
            hasEmailError.value = false;
          }
          if (hasPasswordError.value) {
            hasPasswordError.value = false;
          }
        }

        emailController.addListener(listener);
        passwordController.addListener(listener);
        serverEndpointController.addListener(listener);

        return () {
          emailController.removeListener(listener);
          passwordController.removeListener(listener);
          serverEndpointController.removeListener(listener);
        };
      },
      [],
    );

    Future<void> checkVersionMismatch() async {
      try {
        final packageInfo = await PackageInfo.fromPlatform();
        final appVersion = packageInfo.version;
        final appMajorVersion = int.parse(appVersion.split('.')[0]);
        final appMinorVersion = int.parse(appVersion.split('.')[1]);
        final serverMajorVersion = serverInfo.serverVersion.major;
        final serverMinorVersion = serverInfo.serverVersion.minor;

        if (serverMajorVersion == 0 && serverMinorVersion == 0) {
          warningMessage.value = null;
          return;
        }

        final message = getVersionCompatibilityMessage(
          appMajorVersion,
          appMinorVersion,
          serverMajorVersion,
          serverMinorVersion,
        );

        if (message != null) {
          warningMessage.value = message;
        } else {
          warningMessage.value = null;
        }
      } catch (error) {
        warningMessage.value = 'login_form_version_check_error'.tr();
      }
    }

    Future<void> getServerAuthSettings() async {
      warningMessage.value = null;
      hasEmailError.value = false;
      hasPasswordError.value = false;

      final sanitizeServerUrl = sanitizeUrl(serverEndpointController.text);
      final serverUrl = punycodeEncodeUrl(sanitizeServerUrl);

      if (serverUrl.isEmpty) {
        warningMessage.value = "login_form_server_empty".tr();
        return;
      }

      try {
        isLoadingServer.value = true;
        final endpoint =
            await ref.read(authProvider.notifier).validateServerUrl(serverUrl);

        await ref.read(serverInfoProvider.notifier).getServerInfo();
        await checkVersionMismatch();

        serverEndpoint.value = endpoint;
      } on ApiException catch (e) {
        warningMessage.value = e.message ?? 'login_form_api_exception'.tr();
        isLoadingServer.value = false;
      } on HandshakeException {
        warningMessage.value = 'login_form_handshake_exception'.tr();
        isLoadingServer.value = false;
      } catch (e) {
        warningMessage.value = 'login_form_server_error'.tr();
        isLoadingServer.value = false;
      } finally {
        isLoadingServer.value = false;
      }
    }

    useEffect(
      () {
        final serverUrl = getServerUrl();
        if (serverUrl != null) {
          serverEndpointController.text = serverUrl;
        }
        return null;
      },
      [],
    );

    void populateTestLoginInfo() {
      warningMessage.value = null;
      hasEmailError.value = false;
      hasPasswordError.value = false;
      emailController.text = 'demo@immich.app';
      passwordController.text = 'demo';
      serverEndpointController.text = 'https://demo.immich.app';
    }

    Future<void> login() async {
      // Don't proceed if form isn't valid
      if (!isFormValid.value) return;

      TextInput.finishAutofillContext();
      FocusScope.of(context).unfocus();
      warningMessage.value = null;
      hasEmailError.value = false;
      hasPasswordError.value = false;

      // First validate the form fields
      if (!loginFormKey.currentState!.validate()) {
        return;
      }

      isLoading.value = true;
      invalidateAllApiRepositoryProviders(ref);

      try {
        await getServerAuthSettings();

        final result = await ref.read(authProvider.notifier).login(
              emailController.text,
              passwordController.text,
            );

        if (result.shouldChangePassword && !result.isAdmin) {
          context.pushRoute(const ChangePasswordRoute());
        } else {
          if (localAuthState.canAuthenticate) {
            final shouldAddBiometric = await showDialog<bool>(
              context: context,
              builder: (BuildContext context) {
                return AlertDialog(
                  title: const Text('login_form_add_security_title').tr(),
                  content: const Text('login_form_add_security_content').tr(),
                  actions: <Widget>[
                    TextButton(
                      child: const Text('login_form_not_now').tr(),
                      onPressed: () => Navigator.of(context).pop(false),
                    ),
                    TextButton(
                      child: const Text('common_yes').tr(),
                      onPressed: () => Navigator.of(context).pop(true),
                    ),
                  ],
                );
              },
            );

            if (shouldAddBiometric == true) {
              await Store.put(StoreKey.enableBiometric, true);
            }
          }

          context.replaceRoute(const CuratorOnboardingRoute());
        }
      } on ApiException catch (e) {
        if (e.code == 401) {
          hasEmailError.value = true;
          hasPasswordError.value = true;
          warningMessage.value = 'Incorrect email or password';
        } else {
          warningMessage.value = e.message ?? 'login_form_api_exception'.tr();
        }
      } catch (error) {
        warningMessage.value = "login_form_failed_login".tr();
      } finally {
        isLoading.value = false;
      }
    }

    buildVersionCompatWarning() {
      if (warningMessage.value == null) {
        return [const SizedBox.shrink()];
      }

      return [
        Container(
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0x1FF44336),
            borderRadius: BorderRadius.circular(12),
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Icon(Icons.error, color: Color(0xFFF44336)),
              const SizedBox(width: 16.0),
              Expanded(
                child: Text(warningMessage.value!),
              ),
            ],
          ),
        ),
        const SizedBox(height: 24.0),
      ];
    }

    Widget buildServerEndpointInputField() {
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          double maxWidth = constraints.maxWidth;
          return RawAutocomplete<String>(
            textEditingController: serverEndpointController,
            focusNode: serverEndpointFocusNode,
            optionsBuilder: (value) {
              return ['1', '2', '3'];
            },
            displayStringForOption: (value) => value,
            onSelected: (value) => {},
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
              return ServerEndpointInput(
                controller: serverEndpointController,
                focusNode: serverEndpointFocusNode,
                onSubmit: passwordFocusNode.requestFocus,
                padding: EdgeInsets.zero,
              );
            },
            optionsViewBuilder: (context, onSelected, options) {
              return Align(
                alignment: Alignment.topLeft,
                child: Material(
                  elevation: 4,
                  borderRadius: BorderRadius.circular(12),
                  clipBehavior: Clip.antiAlias,
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      maxHeight: 300,
                      minWidth: maxWidth,
                      maxWidth: maxWidth,
                    ),
                    child: ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (_, index) {
                        final option = options.elementAt(index);
                        return ListTile(
                          title: Text(option),
                          onTap: () {
                            serverEndpointController.text = option;
                            passwordFocusNode.requestFocus();
                          },
                        );
                      },
                    ),
                  ),
                ),
              );
            },
          );
        },
      );
    }

    Widget buildLogin() {
      return Form(
        key: loginFormKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              EmailInput(
                controller: emailController,
                focusNode: emailFocusNode,
                onSubmit: serverEndpointFocusNode.requestFocus,
                hasExternalError: hasEmailError.value,
              ),
              const SizedBox(height: 32.0),
              buildServerEndpointInputField(),
              const SizedBox(height: 32.0),
              PasswordInput(
                controller: passwordController,
                focusNode: passwordFocusNode,
                onSubmit: isFormValid.value
                    ? login
                    : null, // Only allow submit if form is valid
                hasExternalError: hasPasswordError.value,
              ),
              const SizedBox(height: 24.0),
              GestureDetector(
                // onTap: () => context.pushRoute(const CuratorOnboardingRoute()),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    'Reset Password',
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontSize: 14.0,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24.0),
              ...buildVersionCompatWarning(),
              SizedBox(
                height: 100.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    isLoading.value
                        ? const LoadingIcon(
                            text: 'Logging in to your account',
                          )
                        : LoginButton(
                            onPressed: isFormValid.value ? login : () {},
                            withIcon: false,
                            isDisabled: !isFormValid.value,
                          ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    Widget buildLogo(BuildContext context) {
      return GestureDetector(
        onDoubleTap: () => populateTestLoginInfo(),
        child: SvgPicture.asset(
          context.isDarkTheme
              ? 'assets/curator-photos-logo-dark.svg'
              : 'assets/curator-photos-logo-light.svg',
          height: 40,
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        return SingleChildScrollView(
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: constraints.maxHeight),
            child: Center(
              child: SizedBox(
                width: 312,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    buildLogo(context),
                    const SizedBox(height: 24.0),
                    buildLogin(),
                  ],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
