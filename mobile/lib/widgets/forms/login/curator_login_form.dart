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
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/local_auth.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/provider_utils.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:immich_mobile/utils/version_compatibility.dart';
import 'package:immich_mobile/widgets/forms/login/device_selector.dart';
import 'package:immich_mobile/widgets/forms/login/loading_icon.dart';
import 'package:immich_mobile/widgets/forms/login/login_button.dart';
import 'package:immich_mobile/widgets/forms/login/password_input.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/providers/device_path_refresh.provider.dart';

import 'package:homecloud_frontend/homecloud_frontend.dart';

class CuratorLoginForm extends HookConsumerWidget {
  final log = Logger('LoginForm');
  final VoidCallback switchToRemoteAccessForm;

  CuratorLoginForm({super.key, required this.switchToRemoteAccessForm});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final passwordController = useTextEditingController.fromValue(TextEditingValue.empty);
    final deviceController = useTextEditingController.fromValue(TextEditingValue.empty);

    final passwordFocusNode = useFocusNode();
    final deviceFocusNode = useFocusNode();

    final email = useState<String>('');

    final isLoading = useState<bool>(false);
    final hasPreviousLoginFailed = useState<bool>(false);

    final warningMessage = useState<String?>(null);
    final hasEmailError = useState<bool>(false);
    final hasPasswordError = useState<bool>(false);

    final formKey = useMemoized<GlobalKey<FormState>>(() => GlobalKey<FormState>());

    final serverInfo = ref.watch(serverInfoProvider);
    final localAuthState = ref.watch(localAuthProvider);

    final discovery = ref.watch(deviceDiscoveryProvider);

    /// Change focus from one field to another
    void fieldFocusChange(BuildContext context, FocusNode currentFocus, FocusNode nextFocus) {
      currentFocus.unfocus();
      FocusScope.of(context).requestFocus(nextFocus);
    }

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
      if (hasPreviousLoginFailed.value) {
        hasPreviousLoginFailed.value = false;
      }
    }

    bool areRequiredFieldsFilled() =>
        email.value.isNotEmpty && passwordController.text.isNotEmpty && discovery.selectedDevice != null;

    useEffect(() {
      email.value = ref.read(deviceProvider).login;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        discovery.startDeviceDiscovery();
      });
      return null;
    }, []);

    useEffect(() {
      void onFocusChange() {
        final shouldClear =
            warningMessage.value != null ||
            hasEmailError.value ||
            hasPasswordError.value ||
            hasPreviousLoginFailed.value;
        if (!shouldClear) return;
        if (passwordFocusNode.hasFocus && hasPasswordError.value) {
          hasPasswordError.value = false;
        }
        if (warningMessage.value != null) {
          warningMessage.value = null;
        }
        if (hasPreviousLoginFailed.value) {
          hasPreviousLoginFailed.value = false;
        }
      }

      passwordFocusNode.addListener(onFocusChange);

      return () {
        passwordFocusNode.removeListener(onFocusChange);
      };
    }, []);

    useEffect(() {
      return null;
    }, []);

    void populateDevCredentials() async {
      const env = String.fromEnvironment('ENVIRONMENT', defaultValue: 'prod');
      await dotenv.load(fileName: '.env.$env');
      final serverUrl = dotenv.env['DEV_SERVER_URL'];
      final emailValue = dotenv.env['DEV_EMAIL'];
      final password = dotenv.env['DEV_PASSWORD'];

      clearAllErrors();
      email.value = emailValue ?? '';
      passwordController.text = password ?? '';

      if (serverUrl != null && serverUrl.isNotEmpty) {
        discovery.selectDevice(
          DeviceItem(baseUrl: Uri.parse(serverUrl), about: null, status: null, isTemporary: true),
        );
      }
    }

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
      final device = discovery.selectedDevice;
      if (device == null) {
        warningMessage.value = "login_form_no_device_selected".tr();
        return false;
      }
      final baseUrl =
          '${device.baseUrl!.scheme}://${device.baseUrl!.host}${device.baseUrl!.port != 80 && device.baseUrl!.port != 443 ? ':${device.baseUrl!.port}' : ''}/photos';

      clearAllErrors();
      final sanitizedServerUrl = sanitizeUrl(baseUrl.toString());
      final normalizedServerUrl = punycodeEncodeUrl(sanitizedServerUrl);

      if (normalizedServerUrl.isEmpty) {
        warningMessage.value = "login_form_server_empty".tr();
        return false;
      }

      try {
        await ref.read(authProvider.notifier).validateServerUrl(normalizedServerUrl);

        await ref.read(serverInfoProvider.notifier).getServerInfo();
        await updateVersionCompatibilityWarning();

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

    Future<void> handleSyncFlow() async {
      final backgroundManager = ref.read(backgroundSyncProvider);

      await backgroundManager.syncLocal(full: true);
      await backgroundManager.syncRemote();
      await backgroundManager.hashAssets();

      if (Store.get(StoreKey.syncAlbums, false)) {
        await backgroundManager.syncLinkedAlbum();
      }
    }


    Future<void> login() async {
      if (hasPreviousLoginFailed.value) {
        return;
      }

      TextInput.finishAutofillContext();
      FocusScope.of(context).unfocus();

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

        final result = await ref.read(authProvider.notifier).login(email.value, passwordController.text);

        // Refresh device paths after successful login
        discovery.connectToDevice();
        final device = discovery.selectedDevice;
        final paths = device?.paths;
        if (paths != null && paths.isNotEmpty) {
          await ref.read(devicePathRefreshServiceProvider).processAndSavePaths(paths);
        }

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
                    TextButton(child: const Text('common_yes').tr(), onPressed: () => Navigator.of(context).pop(true)),
                  ],
                );
              },
            );

            if (shouldAddBiometric == true) {
              await Store.put(StoreKey.enableBiometric, true);
            }
          }

          final onboardingWasShown = Store.tryGet(StoreKey.onboardingWasShown) ?? false;
          if (onboardingWasShown) {
            if (onboardingWasShown) {
              final isBeta = Store.isBetaTimelineEnabled;
              if (isBeta) {
                await ref.read(galleryPermissionNotifier.notifier).requestGalleryPermission();
                handleSyncFlow();
                ref.read(websocketProvider.notifier).connect();
                context.replaceRoute(const TabShellRoute());
                return;
              }
              context.replaceRoute(const TabControllerRoute());
            } else {
              context.replaceRoute(const CuratorOnboardingRoute());
            }
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
        debugPrint("login_form_failed_login: $error");
        warningMessage.value = "login_form_failed_login".tr();
        hasPreviousLoginFailed.value = true;
      } finally {
        isLoading.value = false;
      }
    }

    return Column(
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        GestureDetector(
          onDoubleTap: () => populateDevCredentials(),
          child: Column(
            children: [
              const Image(width: 140.0, height: 140.0, image: AssetImage('assets/curator-photos-logo.png')),
              SvgPicture.asset(
                context.isDarkTheme ? 'assets/curator-photos-logo-dark.svg' : 'assets/curator-photos-logo-light.svg',
                height: 40,
              ),
            ],
          ),
        ),
        const SizedBox(height: 24.0),
        isLoading.value
            ? LoadingIcon(key: const ValueKey("loading"), text: 'curator.login_form_loading_text'.tr())
            : Column(
                children: [
                  Form(
                    key: formKey,
                    child: AutofillGroup(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Text(
                            email.value,
                            textAlign: TextAlign.center,
                            style: const TextStyle(fontSize: 16.0, fontWeight: FontWeight.w400),
                          ),
                          const SizedBox(height: 24.0),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return DeviceSelector(
                                controller: deviceController,
                                devices: discovery.devices.values.toList(),
                                maxWidth: constraints.maxWidth,
                                selectedDevice: discovery.selectedDevice,
                                isDetecting: discovery.isDetecting,
                                focusNode: deviceFocusNode,
                                enabled: !isLoading.value,
                                onDeviceSelected: (device) {
                                  discovery.selectDevice(device);
                                  fieldFocusChange(context, deviceFocusNode, passwordFocusNode);
                                },
                                onRefresh: discovery.startDeviceDiscovery,
                              );
                            },
                          ),
                          const SizedBox(height: 24.0),
                          PasswordInput(
                            controller: passwordController,
                            focusNode: passwordFocusNode,
                            onSubmit: login,
                            hasExternalError: hasPasswordError.value,
                          ),
                          const SizedBox(height: 24.0),
                          GestureDetector(
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
                          warningMessage.value == null
                              ? const SizedBox.shrink()
                              : Column(
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
                                          Expanded(child: Text(warningMessage.value!)),
                                        ],
                                      ),
                                    ),
                                    const SizedBox(height: 24.0),
                                  ],
                                ),
                          AnimatedBuilder(
                            animation: Listenable.merge([passwordController, hasPreviousLoginFailed]),
                            builder: (_, __) {
                              final canSubmit = areRequiredFieldsFilled() && !hasPreviousLoginFailed.value;
                              return LoginButton(onPressed: login, withIcon: false, isDisabled: !canSubmit);
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
      ],
    );
  }
}
