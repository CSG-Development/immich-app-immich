import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
    final hasPreviousLoginFailed = useState<bool>(false);
    final warningMessage = useMemoized(() => ValueNotifier<String?>(null));
    final hasEmailError = useMemoized(() => ValueNotifier<bool>(false));
    final hasPasswordError = useMemoized(() => ValueNotifier<bool>(false));
    final hasServerEndpointError =
        useMemoized(() => ValueNotifier<bool>(false));

    final formKey =
        useMemoized<GlobalKey<FormState>>(() => GlobalKey<FormState>());

    final serverEndpoint = useState<String?>(null);
    final serverInfo = ref.watch(serverInfoProvider);
    final localAuthState = ref.watch(localAuthProvider);

    void clearAllErrors() {
      if (warningMessage.value != null) {
        warningMessage.value = null;
      }
      if (hasEmailError.value) {
        hasEmailError.value = false;
      }
      if (hasPasswordError.value) {
        hasPasswordError.value = false;
      }
      if (hasServerEndpointError.value) {
        hasServerEndpointError.value = false;
      }
      if (hasPreviousLoginFailed.value) {
        hasPreviousLoginFailed.value = false;
      }
    }

    bool areRequiredFieldsFilled() =>
        emailController.text.isNotEmpty &&
        passwordController.text.isNotEmpty &&
        serverEndpointController.text.isNotEmpty;

    useEffect(
      () {
        void onFocusChange() {
          final shouldClear = warningMessage.value != null ||
              hasEmailError.value ||
              hasPasswordError.value ||
              hasServerEndpointError.value ||
              hasPreviousLoginFailed.value;
          if (!shouldClear) return;
          if (emailFocusNode.hasFocus ||
              passwordFocusNode.hasFocus ||
              serverEndpointFocusNode.hasFocus) {
            clearAllErrors();
          }
        }

        emailFocusNode.addListener(onFocusChange);
        passwordFocusNode.addListener(onFocusChange);
        serverEndpointFocusNode.addListener(onFocusChange);

        return () {
          emailFocusNode.removeListener(onFocusChange);
          passwordFocusNode.removeListener(onFocusChange);
          serverEndpointFocusNode.removeListener(onFocusChange);
        };
      },
      [],
    );

    useEffect(
      () {
        return () {
          warningMessage.dispose();
          hasEmailError.dispose();
          hasPasswordError.dispose();
          hasServerEndpointError.dispose();
        };
      },
      [],
    );

    Future<void> updateVersionCompatibilityWarning() async {
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
        warningMessage.value = 'curator.login_form_version_check_error'.tr();
      }
    }

    Future<bool> fetchServerAuthSettings() async {
      clearAllErrors();

      final sanitizedServerUrl = sanitizeUrl(serverEndpointController.text);
      final normalizedServerUrl = punycodeEncodeUrl(sanitizedServerUrl);

      if (normalizedServerUrl.isEmpty) {
        warningMessage.value = "login_form_server_empty".tr();
        return false;
      }

      try {
        final endpoint = await ref
            .read(authProvider.notifier)
            .validateServerUrl(normalizedServerUrl);

        await ref.read(serverInfoProvider.notifier).getServerInfo();
        await updateVersionCompatibilityWarning();

        serverEndpoint.value = endpoint;
        return true;
      } on ApiException catch (e) {
        warningMessage.value = e.message ?? 'login_form_api_exception'.tr();
        return false;
      } on HandshakeException {
        warningMessage.value = 'login_form_handshake_exception'.tr();
        return false;
      } catch (e) {
        warningMessage.value = 'login_form_server_error'.tr();
        return false;
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

    void populateDevCredentials() async {
      const env = String.fromEnvironment('ENVIRONMENT', defaultValue: 'prod');
      await dotenv.load(fileName: '.env.$env');
      final serverUrl = dotenv.env['DEV_SERVER_URL'];
      final email = dotenv.env['DEV_EMAIL'];
      final password = dotenv.env['DEV_PASSWORD'];

      clearAllErrors();
      emailController.text = email ?? '';
      passwordController.text = password ?? '';
      serverEndpointController.text = serverUrl ?? '';
    }

    String? validateEmail(String email) {
      final simpleEmailPattern = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
      if (!simpleEmailPattern.hasMatch(email)) {
        return 'login_form_err_invalid_email'.tr();
      }
      return null;
    }

    String? validateServerEndpoint(String url) {
      final parsedUrl = Uri.tryParse(sanitizeUrl(url));
      if (parsedUrl == null ||
          !parsedUrl.isAbsolute ||
          !parsedUrl.scheme.startsWith("http") ||
          parsedUrl.host.isEmpty) {
        return 'login_form_err_invalid_url'.tr();
      }

      return null;
    }

    Future<void> login() async {
      if (hasPreviousLoginFailed.value) {
        return;
      }
      if (!areRequiredFieldsFilled()) {
        return;
      }

      TextInput.finishAutofillContext();
      FocusScope.of(context).unfocus();

      final serverEndpointValidationError =
          validateServerEndpoint(serverEndpointController.text);

      if (serverEndpointValidationError != null) {
        hasServerEndpointError.value = true;
        warningMessage.value = serverEndpointValidationError;
        hasPreviousLoginFailed.value = true;
        return;
      }

      final emailValidationError = validateEmail(emailController.text);

      if (emailValidationError != null) {
        hasEmailError.value = true;
        warningMessage.value = emailValidationError;
        hasPreviousLoginFailed.value = true;
        return;
      }

      if (!areRequiredFieldsFilled()) {
        hasPreviousLoginFailed.value = true;
        return;
      }

      clearAllErrors();

      if (!formKey.currentState!.validate()) {
        return;
      }

      isLoading.value = true;

      try {
        final isServerValid = await fetchServerAuthSettings();

        if (!isServerValid) {
          return;
        }

        invalidateAllApiRepositoryProviders(ref);

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

          final onboardingWasShown =
              Store.tryGet(StoreKey.onboardingWasShown) ?? false;
          if (onboardingWasShown) {
            context.replaceRoute(const TabControllerRoute());
          } else {
            context.replaceRoute(const CuratorOnboardingRoute());
          }
        }
      } on ApiException catch (e) {
        if (e.code == 400 || e.code == 401) {
          hasEmailError.value = true;
          hasPasswordError.value = true;
          warningMessage.value = 'errors.incorrect_email_or_password'.tr();
        } else {
          warningMessage.value = e.message ?? 'login_form_api_exception'.tr();
        }
        hasPreviousLoginFailed.value = true;
      } catch (error) {
        warningMessage.value = "login_form_failed_login".tr();
        hasPreviousLoginFailed.value = true;
      } finally {
        isLoading.value = false;
      }
    }

    Widget buildWarningBanner() {
      return ValueListenableBuilder<String?>(
        valueListenable: warningMessage,
        builder: (_, message, __) {
          if (message == null) {
            return const SizedBox.shrink();
          }
          return Column(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0x1FF44336),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Icons.error,
                      color: context.isDarkTheme
                          ? const Color(0xFFF28F8C)
                          : const Color(0xFFF44336),
                    ),
                    const SizedBox(width: 16.0),
                    Expanded(
                      child: Text(message),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24.0),
            ],
          );
        },
      );
    }

    Widget buildServerEndpointAutocomplete() {
      return LayoutBuilder(
        builder: (BuildContext context, BoxConstraints constraints) {
          final double maxWidth = constraints.maxWidth;
          return RawAutocomplete<String>(
            textEditingController: serverEndpointController,
            focusNode: serverEndpointFocusNode,
            optionsBuilder: (value) {
              const allOptions = ['1', '2', '3'];
              final input = value.text.trim();
              if (input.isEmpty) return allOptions;
              return allOptions.where(
                (option) => option.toLowerCase().contains(input.toLowerCase()),
              );
            },
            displayStringForOption: (value) => value,
            onSelected: (value) {
              serverEndpointController.text = value;
              passwordFocusNode.requestFocus();
            },
            fieldViewBuilder:
                (context, controller, focusNode, onFieldSubmitted) {
              return ValueListenableBuilder<bool>(
                valueListenable: hasServerEndpointError,
                builder: (_, serverError, __) {
                  return ServerEndpointInput(
                    controller: serverEndpointController,
                    focusNode: serverEndpointFocusNode,
                    onSubmit: passwordFocusNode.requestFocus,
                    hasExternalError: serverError,
                  );
                },
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
                            onSelected(option);
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

    Widget buildLoginForm() {
      return Form(
        key: formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              ValueListenableBuilder<bool>(
                valueListenable: hasEmailError,
                builder: (_, emailError, __) {
                  return EmailInput(
                    controller: emailController,
                    focusNode: emailFocusNode,
                    onSubmit: serverEndpointFocusNode.requestFocus,
                    hasExternalError: emailError,
                  );
                },
              ),
              const SizedBox(height: 32.0),
              buildServerEndpointAutocomplete(),
              const SizedBox(height: 32.0),
              ValueListenableBuilder<bool>(
                valueListenable: hasPasswordError,
                builder: (_, passwordError, __) {
                  return PasswordInput(
                    controller: passwordController,
                    focusNode: passwordFocusNode,
                    onSubmit: login,
                    hasExternalError: passwordError,
                  );
                },
              ),
              const SizedBox(height: 24.0),
              GestureDetector(
                // onTap: () => context.pushRoute(const CuratorOnboardingRoute()),
                child: Padding(
                  padding: const EdgeInsets.all(12.0),
                  child: Text(
                    'reset_password'.tr(),
                    style: TextStyle(
                      color: Theme.of(context).primaryColor,
                      fontSize: 14.0,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 24.0),
              buildWarningBanner(),
              SizedBox(
                height: 100.0,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    isLoading.value
                        ? LoadingIcon(
                            key: const ValueKey("loading"),
                            text: 'curator.login_form_loading_text'.tr(),
                          )
                        : AnimatedBuilder(
                            animation: Listenable.merge([
                              emailController,
                              passwordController,
                              serverEndpointController,
                              hasPreviousLoginFailed,
                            ]),
                            builder: (_, __) {
                              final canSubmit = areRequiredFieldsFilled() &&
                                  !hasPreviousLoginFailed.value;
                              return LoginButton(
                                onPressed: canSubmit ? login : () {},
                                withIcon: false,
                                isDisabled: !canSubmit,
                              );
                            },
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
        onDoubleTap: () => populateDevCredentials(),
        child: SvgPicture.asset(
          context.isDarkTheme
              ? 'assets/curator-photos-logo-dark.svg'
              : 'assets/curator-photos-logo-light.svg',
          height: 52,
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
                    buildLoginForm(),
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
