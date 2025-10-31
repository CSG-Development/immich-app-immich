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
import 'package:immich_mobile/utils/debug_print.dart';
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

import 'package:homecloud_frontend/homecloud_frontend.dart';
import 'package:homecloud_frontend/api/api.swagger.dart';
import 'package:homecloud_frontend/api/remote_access.swagger.dart';
import 'package:homecloud_frontend/nsd_wrapper.dart' as nsd;

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

    final favoriteLoggingIn = useState<bool>(false);
    final loggingIn = useState<bool>(false);
    String favoriteDevice = '';

    int remoteInitiateAttempts = 0;
    final selectedDevice = useState<DeviceItem?>(null);
    nsd.Discovery? discovery;
    final devices = useState<Map<String, DeviceItem>>({});
    final counterDetection = useState<int>(0);

    bool isDetecting = counterDetection.value > 0;

    /// Handle API errors by printing them in debug mode
    void handleError(ApiErrorMessage message, dynamic error) {
      dPrint(() => "[SignInScreen] $message: ${extractErrorMessage(error)}");
      log.severe(extractErrorMessage(error));
    }
    late final VoidCallback startLocalAndRemoteDetection;

    void noDeviceFound() {
      dPrint(() => "[SignInScreen] No device found.");

      // Show the Unable To Connect screen in fullscreen dialog
      context.pushRoute(
        UnableToConnectRoute(
          onRetry: () {
            context.pop();
            Future.delayed(const Duration(milliseconds: 300), () {
               startLocalAndRemoteDetection();
            });
          },
        ),
      );
    }

    void updateDetectionCounter(int delta) {
      if (context.mounted) {
        counterDetection.value += delta;
        if (counterDetection.value == 0 && !ref.read(deviceProvider).deviceFound) {
          favoriteLoggingIn.value = false;
          dPrint(() => "[SignInScreen] Detection finished, found devices: ${devices.value.length}");
          // No device found after detection
          if (devices.value.isEmpty) {
            noDeviceFound();
          }
          // Auto-select favorite device if found
          else if (selectedDevice.value == null) {
            selectedDevice.value = devices.value.values.firstWhere(
              (device) => device.about?.certificateCommonName == favoriteDevice,
              orElse: () => devices.value.values.first,
            );
            dPrint(() => "[SignInScreen] Auto-selecting device: ${selectedDevice.value!.about?.certificateCommonName}");
          }
        }
      }
    }

    /// Stop mDNS detection
    Future<void> _stopDiscovery() async {
      if (discovery != null) {
        stopDiscovery(discovery!);
        discovery = null;
        updateDetectionCounter(-1);
      }
    }

    /// Get the about information of the device and add it to the list of devices.
    ///
    /// If the device is the favorite device and already authenticated, set it in the provider and go to dashboard
    Future<bool> getDeviceAbout(Api api, Uri baseUrl, Status status) async {
      try {
        final response = await api.aboutGet();
        if (response.isSuccessful) {
          final device = DeviceItem(baseUrl: baseUrl, about: response.body!, status: status);
          // Auto-login if is the favorite device and already authenticated
          if (device.about?.certificateCommonName == favoriteDevice &&
              context.mounted &&
              ref.read(deviceProvider).isAuthenticated) {
            // Set device then go to dashboard
            ref.read(deviceProvider.notifier).setHost(baseUrl: device.baseUrl, status: device.status, save: false);
            _stopDiscovery();
            // TODO Implement passwordless login
            showDialog(
              context: context,
              builder: (context) => AlertDialog(
                title: const Text('Not implemented'),
                content: const Text('Device found, but the authentication flow is not implemented.'),
                actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: const Text('OK'))],
              ),
            );
          }
          // Else add to the list of devices
          else {
            // Avoid duplicates between mDNS and remote detection
            // Don't worry about overwriting, the remote device contains also the local paths ;)
            if (context.mounted) {
              dPrint(() => "[SignInScreen] Adding device: ${device.name} at ${device.baseUrl}");
            }

            devices.value = {...devices.value, device.about!.certificateCommonName: device};
          }
          // Device added
          return true;
        } else {
          handleError(ApiErrorMessage.aboutGet, response);
        }
      } catch (error) {
        handleError(ApiErrorMessage.aboutGet, error);
      }
      // Device not added
      return false;
    }

    /// Check the status of a device at the given baseUrl.
    ///
    /// Then if the device is set up, get its about information.
    ///
    /// If everything is ok, add the device to the list of devices.
    Future<bool> checkDeviceStatus({required Uri baseUrl, int timeoutDelay = 1000}) async {
      dPrint(() => "[SignInScreen] checkDeviceStatus: $baseUrl");
      try {
        final api = DeviceProvider.createApi(baseUrl: baseUrl);
        final response = await api.statusGet().timeout(Duration(milliseconds: timeoutDelay));

        if (response.isSuccessful) {
          final status = response.body!;
          dPrint(() => "[SignInScreen] Device status response for ${baseUrl.host}: ${status.toString()}");
          // Add only if the device is set up
          if (status.oobe.done) {
            return getDeviceAbout(api, baseUrl, status);
          }
        } else {
          handleError(ApiErrorMessage.statusGet, response);
        }
      } catch (error) {
        handleError(ApiErrorMessage.statusGet, error);
      }
      // Device not added
      return false;
    }

    /// Try to add a remote device using its paths
    /// Paths are ordered by priority (local first, Public then relay) by the server
    Future<void> addRemoteDevice(Device device, DevicePaths devicePaths) async {
      updateDetectionCounter(1);
      int i = 0;
      bool deviceAdded = false;
      while (i < devicePaths.paths.length && !deviceAdded) {
        var path = devicePaths.paths[i];
        final Uri baseUrl = DeviceProvider.createBaseUrl(path.address, path.port);
        dPrint(() => "[SignInScreen] Checking remote device with ${path.type.value} path: $baseUrl");

        deviceAdded = await checkDeviceStatus(
          baseUrl: baseUrl,
          timeoutDelay: path.type == DevicePathType.local ? 60 * 1000 : 20 * 3000,
        );
        i++;
      }
      updateDetectionCounter(-1);
    }

    /// Get remote devices from the remote refresh token
    Future<void> getRemoteDevices() async {
      final isAuthenticated = ref.read(remoteProvider).isAuthenticated;
      if (!isAuthenticated) {
        return;
      }
      try {
        updateDetectionCounter(1);
        final remoteApi = ref.read(remoteProvider).api;
        final responseList = await remoteApi.clientV1DevicesGet();
        dPrint(
          () => "[SignInScreen] Remote devices GET response: ${responseList.isSuccessful}, body: ${responseList.body}",
        );
        if (responseList.isSuccessful) {
          final List<Device>? remoteDevices = responseList.body;
          if (remoteDevices != null && remoteDevices.isNotEmpty) {
            dPrint(() => "[SignInScreen] Found ${remoteDevices.length} remote devices.");
            // Get paths of each remote device
            for (Device remoteDevice in remoteDevices) {
              dPrint(() => "[SignInScreen] Processing remote device: ${remoteDevice.friendlyName}");
              // Already added from mDNS detection
              // if (devices.value.containsKey(remoteDevice.certificateCommonName)) {
              //   dPrint(() => "[SignInScreen] Remote device already added: ${remoteDevice.friendlyName}");
              //   if (isDevEnvironment) {
              //     dPrint(() => "[SignInScreen] Skip for dev environment");
              //   } else {
              //     continue;
              //   }
              // }
              dPrint(() => "[SignInScreen] ${remoteDevice.seagateDeviceID}");
              // Get paths of the remote device
              final responseInfo = await remoteApi.clientV1DevicesDeviceIDGet(deviceID: remoteDevice.seagateDeviceID);
              dPrint(
                () =>
                    "[SignInScreen] Device paths GET for ${remoteDevice.friendlyName}: ${responseInfo.isSuccessful}, body: ${responseInfo.body}",
              );
              // Try to add device using the priority list
              if (responseInfo.isSuccessful) {
                addRemoteDevice(remoteDevice, responseInfo.body!);
              } else {
                handleError(ApiErrorMessage.remoteApi, responseInfo);
              }
            }
          }
        } else {
          // If unauthorized or forbidden, try to re-initiate the authentication
          if (responseList.statusCode == 401 || responseList.statusCode == 403) {
            if (remoteInitiateAttempts < 2) {
              remoteInitiateAttempts++;
              dPrint(
                () =>
                    "[SignInScreen] Unauthorized or forbidden when fetching remote devices. Attempt: $remoteInitiateAttempts",
              );
              Future.delayed(const Duration(seconds: 1), () {
                switchToRemoteAccessForm();
              });
            }
          }
          handleError(ApiErrorMessage.remoteApi, responseList);
        }
      } catch (error) {
        handleError(ApiErrorMessage.remoteApi, error);
      }
      updateDetectionCounter(-1);
    }

    /// Start mDNS detection of local devices
    Future<void> startNsdDetection() async {
      if (discovery != null) {
        return; // Already detecting, avoid duplicate calls
      }
      updateDetectionCounter(1);
      discovery = await startDiscovery();
      if (discovery != null && context.mounted) {
        // Add a listener to find device
        discovery?.addServiceListener((service, status) {
          if (status == nsd.ServiceStatus.found && service.name!.contains(serviceNameDiscover) && context.mounted) {
            dPrint(() => "[SignInScreen] mDNS Device Found: ${service.toString()}");
            checkDeviceStatus(
              baseUrl: DeviceProvider.createBaseUrl(service.host!, service.port),
              timeoutDelay: 12 * 5000,
            );
          }
        });
        // Stop discovery after x seconds if no device found
        Future.delayed(durationDetection, () {
          _stopDiscovery();
        });
      } else {
        updateDetectionCounter(-1);
      }
    }

    startLocalAndRemoteDetection = () {
      devices.value = {};
      selectedDevice.value = null;
      startNsdDetection();
      getRemoteDevices();
    };

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
        email.value.isNotEmpty && passwordController.text.isNotEmpty && selectedDevice.value != null;

    useEffect(() {
      email.value = ref.read(deviceProvider).login;
      // Authenticated but need to find the device
      favoriteDevice = ref.read(deviceProvider).deviceID ?? '';
      favoriteLoggingIn.value = favoriteDevice.isNotEmpty && ref.read(deviceProvider).isAuthenticated;
      // Start detection of local and remote devices
      startLocalAndRemoteDetection();
      return () {
        try {
          passwordController.dispose();
          passwordFocusNode.dispose();
          deviceFocusNode.dispose();
        } catch (e) {
          // Ignore
        }
        _stopDiscovery();
      };
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
      return () {
        warningMessage.dispose();
        hasEmailError.dispose();
        hasPasswordError.dispose();
      };
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

      devices.value = {...devices.value, 'noveo device': DeviceItem(baseUrl: Uri.parse(serverUrl ?? ''))};
      selectedDevice.value = devices.value.entries.firstWhere((item) => item.key == 'noveo device').value;
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
      final device = selectedDevice.value!;
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
                            style: const TextStyle(
                              fontSize: 16.0,
                              fontWeight: FontWeight.w400,
                            ),
                          ),
                          const SizedBox(height: 24.0),
                          LayoutBuilder(
                            builder: (context, constraints) {
                              return DeviceSelector(
                                controller: deviceController,
                                devices: devices.value.entries.map((entry) => entry.value).toList(),
                                maxWidth: constraints.maxWidth,
                                selectedDevice: selectedDevice.value,
                                isDetecting: isDetecting,
                                focusNode: deviceFocusNode,
                                enabled: !loggingIn.value,
                                onDeviceSelected: (device) {
                                  selectedDevice.value = device;
                                  fieldFocusChange(context, deviceFocusNode, passwordFocusNode);
                                },
                                onRefresh: startLocalAndRemoteDetection,
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
                            animation: Listenable.merge([
                              passwordController,
                              hasPreviousLoginFailed,
                            ]),
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
