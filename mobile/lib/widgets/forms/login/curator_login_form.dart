import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
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
import 'package:immich_mobile/widgets/forms/login/device_selector.dart';
import 'package:immich_mobile/widgets/forms/login/email_input.dart';
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
  CuratorLoginForm({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final emailController = useTextEditingController.fromValue(TextEditingValue.empty);
    final passwordController = useTextEditingController.fromValue(TextEditingValue.empty);
    final remoteCodeController = useTextEditingController.fromValue(TextEditingValue.empty);
    final deviceController = useTextEditingController.fromValue(TextEditingValue.empty);

    final emailFocusNode = useFocusNode();
    final passwordFocusNode = useFocusNode();
    final serverEndpointFocusNode = useFocusNode();
    final deviceFocusNode = useFocusNode();
    final remoteCodeFocusNode = useFocusNode();

    final isLoading = useState<bool>(false);
    final hasPreviousLoginFailed = useState<bool>(false);

    final warningMessage = useMemoized(() => ValueNotifier<String?>(null));
    final hasEmailError = useMemoized(() => ValueNotifier<bool>(false));
    final hasPasswordError = useMemoized(() => ValueNotifier<bool>(false));
    final hasServerEndpointError = useMemoized(() => ValueNotifier<bool>(false));
    final formKey = useMemoized<GlobalKey<FormState>>(() => GlobalKey<FormState>());

    final serverEndpoint = useState<String?>(null);

    final serverInfo = ref.watch(serverInfoProvider);
    final localAuthState = ref.watch(localAuthProvider);

    final favoriteLoggingIn = useState<bool>(false);
    final loggingIn = useState<bool>(false);
    String favoriteDevice = '';
    final remoteCodeVisible = useState<bool>(false);
    final remoteCodeLoading = useState<bool>(false);
    final remoteCodeExpired = useState<bool>(false);

    String lastCodeChecked = '';
    String lastRemoteEmail = '';
    String clientFriendlyName = '';

    int remoteInitiateAttempts = 0;
    final remoteCodeErrorText = useState<String?>(null);
    final selectedDevice = useState<DeviceItem?>(null);
    nsd.Discovery? discovery;
    final devices = useState<Map<String, DeviceItem>>({});
    final counterDetection = useState<int>(0);

    bool isDetecting = counterDetection.value > 0;

    /// Handle API errors by printing them in debug mode
    void handleError(ApiErrorMessage message, dynamic error) {
      if (kDebugMode) {
        debugPrint("[SignInScreen] $message: ${extractErrorMessage(error)}");
      }
    }

    void noDeviceFound() {
      if (kDebugMode) {
        debugPrint("[SignInScreen] No device found.");
      }
      // Show the Unable To Connect screen in fullscreen dialog
      // late BuildContext dialogContext;
      // Navigator.of(context).push(
      //   MaterialPageRoute<void>(
      //     fullscreenDialog: true,
      //     builder: (BuildContext context) {
      //       dialogContext = context;
      //       return UnableToConnectScreen(
      //         onRetry: () => {
      //           Navigator.of(dialogContext).pop(),
      //           Future.delayed(
      //             const Duration(milliseconds: 300),
      //             () => startLocalAndRemoteDetection(),
      //           ),
      //         },
      //       );
      //     },
      //   ),
      // );
    }

    void updateDetectionCounter(int delta) {
      if (context.mounted) {
        counterDetection.value += delta;
        if (counterDetection.value == 0 && !ref.read(deviceProvider).deviceFound) {
          favoriteLoggingIn.value = false;
          if (kDebugMode) {
            debugPrint("[SignInScreen] Detection finished, found devices: ${devices.value.length}");
          }
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
            if (kDebugMode) {
              debugPrint("[SignInScreen] Auto-selecting device: ${selectedDevice.value!.about?.certificateCommonName}");
            }
          }
        }
        Future.delayed(const Duration(milliseconds: 300), () {
          if (context.mounted) {
            // TODO: !
            // setState(() {
            //   // Update any relevant state variables here
            // });
          }
        });
      }
    }

    /// Stop mDNS detection
    Future<void> _stopDiscovery(nsd.Discovery? discovery) async {
      debugPrint('_stopDiscovery');
      if (discovery != null) {
        stopDiscovery(discovery);
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
            _stopDiscovery(discovery);
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
            if (kDebugMode && context.mounted) {
              debugPrint("[SignInScreen] Adding device: ${device.name} at ${device.baseUrl}");
            }

            devices.value = {...devices.value, device.about!.certificateCommonName: device};
          }
          if (context.mounted) {
            // TODO: !
            // setState(() {});
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
      try {
        final api = DeviceProvider.createApi(baseUrl: baseUrl);
        final response = await api.statusGet().timeout(Duration(milliseconds: timeoutDelay));
        if (response.isSuccessful) {
          final status = response.body!;
          if (kDebugMode) {
            debugPrint("[SignInScreen] Device status response for ${baseUrl.host}: ${status.toString()}");
          }
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
        if (kDebugMode) {
          debugPrint("[SignInScreen] Checking remote device with ${path.type.value} path: $baseUrl");
        }
        deviceAdded = await checkDeviceStatus(
          baseUrl: baseUrl,
          timeoutDelay: path.type == DevicePathType.local ? 1000 : 3000,
        );
        i++;
      }
      updateDetectionCounter(-1);
    }

    Future<String> getClientFriendlyName() async {
      if (clientFriendlyName.isNotEmpty) {
        return clientFriendlyName;
      }
      final DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();
      // TODO Replace with actual app name
      String name = "Curator Manager";
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
      if (EmailUtils.isEmail(email) && email != lastRemoteEmail && context.mounted && !loggingIn.value) {
        lastRemoteEmail = email;
        // TODO: !
        // setState(() {
        //   // Useful when changing email and requesting a new code
        //   remoteCodeController.clear();
        //   remoteCodeErrorText = null;
        //   remoteCodeExpired = false;
        //   remoteCodeLoading = true;
        // });
        remoteCodeController.clear();
        remoteCodeErrorText.value = null;
        remoteCodeExpired.value = false;
        remoteCodeLoading.value = true;
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
            // Show input for remote access code
            remoteCodeVisible.value = true;
            remoteCodeLoading.value = false;
          } else {
            handleError(ApiErrorMessage.remoteApi, response);
          }
        } catch (error) {
          handleError(ApiErrorMessage.remoteApi, error);
        }
        if (context.mounted) {
          // TODO: !
          // setState(() {});
        }
      }
    }

    /// Get remote devices from the remote refresh token
    Future<void> getRemoteDevices() async {
      try {
        updateDetectionCounter(1);
        final remoteApi = ref.read(remoteProvider).api;
        final responseList = await remoteApi.clientV1DevicesGet();
        if (kDebugMode) {
          debugPrint(
            "[SignInScreen] Remote devices GET response: ${responseList.isSuccessful}, body: ${responseList.body}",
          );
        }
        if (responseList.isSuccessful) {
          final List<Device>? remoteDevices = responseList.body;
          if (remoteDevices != null && remoteDevices.isNotEmpty) {
            if (kDebugMode) {
              debugPrint("[SignInScreen] Found ${remoteDevices.length} remote devices.");
            }
            // Get paths of each remote device
            for (Device remoteDevice in remoteDevices) {
              if (kDebugMode) {
                debugPrint("[SignInScreen] Processing remote device: ${remoteDevice.friendlyName}");
              }
              // Already added from mDNS detection
              if (devices.value.containsKey(remoteDevice.certificateCommonName)) {
                if (kDebugMode) {
                  debugPrint("Remote device already added: ${remoteDevice.friendlyName}");
                }
                continue;
              }
              // Get paths of the remote device
              final responseInfo = await remoteApi.clientV1DevicesDeviceIDGet(deviceID: remoteDevice.seagateDeviceID);
              if (kDebugMode) {
                print(
                  "[SignInScreen] Device paths GET for ${remoteDevice.friendlyName}: ${responseInfo.isSuccessful}, body: ${responseInfo.body}",
                );
              }
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
              if (kDebugMode) {
                debugPrint(
                  "[SignInScreen] Unauthorized or forbidden when fetching remote devices. Attempt: $remoteInitiateAttempts",
                );
              }
              Future.delayed(const Duration(seconds: 1), () {
                initiateRemoteAccess();
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
            if (kDebugMode) {
              debugPrint("[SignInScreen] mDNS Device Found: ${service.toString()}");
            }
            checkDeviceStatus(baseUrl: DeviceProvider.createBaseUrl(service.host!, service.port), timeoutDelay: 5000);
          }
        });
        // Stop discovery after x seconds if no device found
        Future.delayed(durationDetection, () {
          _stopDiscovery(discovery);
        });
      } else {
        updateDetectionCounter(-1);
      }
    }

    void startLocalAndRemoteDetection() {
      devices.value = {};
      selectedDevice.value = null;
      startNsdDetection();
      // If authenticated for remote access, get remote devices
      if (ref.read(remoteProvider).isAuthenticated) {
        lastRemoteEmail = emailController.text;
        getRemoteDevices();
      }
      // Else wait for email to initiate remote access
      else {
        initiateRemoteAccess();
      }
    }

    /// Validate the remote access code and get access and refresh tokens
    ///
    /// Then get the remote devices
    Future<void> checkRemoteAccessCode() async {
      // final tr = AppLocalizations.of(context)!;
      final code = remoteCodeController.text;
      if (code.isNotEmpty && code != lastCodeChecked) {
        lastCodeChecked = code;
        remoteCodeLoading.value = true;
        remoteCodeErrorText.value = null;
        if (context.mounted) {
          // TODO: !
          // setState(() {});
        }
        ;

        try {
          final response = await ref
              .read(remoteProvider)
              .api
              .clientV1AuthTokenPost(
                type: ClientV1AuthTokenPostType.email,
                body: Validate$RequestBody(code: code, reference: ref.read(remoteProvider).reference!),
              );
          if (kDebugMode) {
            debugPrint(
              "[SignInScreen] Remote code validation response: ${response.isSuccessful}, body: ${response.body}",
            );
          }
          // 	Success: JWT access and refresh tokens are returned.
          if (response.isSuccessful) {
            ref.read(remoteProvider.notifier).setAuthToken(auth: response.body!);
            if (kDebugMode) {
              debugPrint("[SignInScreen] Remote access authenticated, fetching remote devices...");
            }
            // Authenticated with the Remote Access server, we can now get remote devices
            getRemoteDevices();
            remoteCodeVisible.value = false;
          } else {
            // Generic error message
            remoteCodeErrorText.value = extractErrorMessage(response);
            // Invalid code
            if (remoteCodeErrorText.value!.contains('invalid')) {
              remoteCodeErrorText.value = 'curator.sign_in_screen_field_remote_code_error_invalid'.tr();
            }
            // Expired code
            else if (remoteCodeErrorText.value!.contains('expired')) {
              remoteCodeExpired.value = true;
              remoteCodeErrorText.value = 'curator.sign_in_screen_field_remote_code_error_expired'.tr();
            }
          }
        }
        // Network error => Remote Access server unreachable?
        catch (error) {
          remoteCodeErrorText.value = 'curator.remote_access_server_unreachable'.tr();
          handleError(ApiErrorMessage.remoteApi, error);
        }
      }
      remoteCodeLoading.value = false;
      if (context.mounted) {
        // TODO: !
        // setState(() {})
      }
      ;
    }

    /// Sign in with the selected device, email and password
    Future _signIn() async {
      // if (_formKey.currentState!.validate() && selectedDevice != null) {
      //   // TODO Implement password login
      //   showDialog(
      //     context: context,
      //     builder: (context) => AlertDialog(
      //       title: const Text('Not implemented'),
      //       content: const Text('You need to implement this feature.'),
      //       actions: [
      //         TextButton(
      //           onPressed: () => Navigator.of(context).pop(),
      //           child: const Text('OK'),
      //         ),
      //       ],
      //     ),
      //   );
      // }
    }

    /// Change focus from one field to another
    void fieldFocusChange(BuildContext context, FocusNode currentFocus, FocusNode nextFocus) {
      currentFocus.unfocus();
      FocusScope.of(context).requestFocus(nextFocus);
    }

    useEffect(() {
      emailController.text = ref.read(deviceProvider).login;
      emailFocusNode.addListener(() {
        if (!emailFocusNode.hasFocus) {
          // Initiate remote access when focus is lost
          initiateRemoteAccess();
        }
      });
      remoteCodeFocusNode.addListener(() {
        if (!remoteCodeFocusNode.hasFocus) {
          // Validate the code when focus is lost
          checkRemoteAccessCode();
        }
      });
      // Authenticated but need to find the device
      favoriteDevice = ref.read(deviceProvider).deviceID ?? '';
      favoriteLoggingIn.value = favoriteDevice.isNotEmpty && ref.read(deviceProvider).isAuthenticated;
      // Start detection of local and remote devices
      startLocalAndRemoteDetection();
      return () {
        try {
          emailController.dispose();
          passwordController.dispose();
          remoteCodeController.dispose();
          remoteCodeFocusNode.dispose();
          emailFocusNode.dispose();
          passwordFocusNode.dispose();
          deviceFocusNode.dispose();
        } catch (e) {
          // Ignore
        }
        _stopDiscovery(discovery);
      };
    }, []);

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
        emailController.text.isNotEmpty && passwordController.text.isNotEmpty && selectedDevice.value != null;

    useEffect(() {
      void onFocusChange() {
        final shouldClear =
            warningMessage.value != null ||
            hasEmailError.value ||
            hasPasswordError.value ||
            hasServerEndpointError.value ||
            hasPreviousLoginFailed.value;
        if (!shouldClear) return;
        if (emailFocusNode.hasFocus || passwordFocusNode.hasFocus || serverEndpointFocusNode.hasFocus) {
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
    }, []);

    useEffect(() {
      return () {
        warningMessage.dispose();
        hasEmailError.dispose();
        hasPasswordError.dispose();
        hasServerEndpointError.dispose();
      };
    }, []);

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

      //TODO: !
      final sanitizedServerUrl = sanitizeUrl(selectedDevice.value!.baseUrl.toString());
      final normalizedServerUrl = punycodeEncodeUrl(sanitizedServerUrl);

      if (normalizedServerUrl.isEmpty) {
        warningMessage.value = "login_form_server_empty".tr();
        return false;
      }

      try {
        final endpoint = await ref.read(authProvider.notifier).validateServerUrl(normalizedServerUrl);

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

    // useEffect(() {
    //   final serverUrl = getServerUrl();
    //   if (serverUrl != null) {
    //     serverEndpointController.text = serverUrl;
    //   }
    //   return null;
    // }, []);

    void populateDevCredentials() async {
      const env = String.fromEnvironment('ENVIRONMENT', defaultValue: 'prod');
      await dotenv.load(fileName: '.env.$env');
      final serverUrl = dotenv.env['DEV_SERVER_URL'];
      final email = dotenv.env['DEV_EMAIL'];
      final password = dotenv.env['DEV_PASSWORD'];

      clearAllErrors();
      emailController.text = email ?? '';
      passwordController.text = password ?? '';

      devices.value = {...devices.value, 'noveo device': DeviceItem(baseUrl: Uri.parse(serverUrl ?? ''))};
      selectedDevice.value = devices.value.entries.firstWhere((item) => item.key == 'noveo device').value;
    }

    String? validateEmail(String email) {
      final simpleEmailPattern = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
      if (!simpleEmailPattern.hasMatch(email)) {
        return 'login_form_err_invalid_email'.tr();
      }
      return null;
    }

    String? validateServerEndpoint(DeviceItem device) {
      final parsedUrl = Uri.tryParse(sanitizeUrl(device.baseUrl.toString()));
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

      final serverEndpointValidationError = validateServerEndpoint(selectedDevice.value!);

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

        final result = await ref.read(authProvider.notifier).login(emailController.text, passwordController.text);

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
                decoration: BoxDecoration(color: const Color(0x1FF44336), borderRadius: BorderRadius.circular(12)),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.error, color: context.isDarkTheme ? const Color(0xFFF28F8C) : const Color(0xFFF44336)),
                    const SizedBox(width: 16.0),
                    Expanded(child: Text(message)),
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
      );
    }

    Widget buildLoginForm() {
      return Form(
        key: formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              buildServerEndpointAutocomplete(),
              const SizedBox(height: 32.0),
              ValueListenableBuilder<bool>(
                valueListenable: hasEmailError,
                builder: (_, emailError, __) {
                  return EmailInput(
                    controller: emailController,
                    focusNode: emailFocusNode,
                    onSubmit: passwordFocusNode.requestFocus,
                    hasExternalError: emailError,
                  );
                },
              ),
              if (remoteCodeVisible.value) const SizedBox(height: 32.0),
              AnimatedSize(
                duration: const Duration(milliseconds: 300),
                curve: Curves.easeInOut,
                alignment: Alignment.topCenter,
                child: remoteCodeVisible.value
                    ? Column(
                        children: [
                          TextFormField(
                            decoration: InputDecoration(
                              labelText: 'curator.sign_in_screen_field_remote_code_label'.tr(),
                              helperText: 'curator.sign_in_screen_field_remote_code_hint'.tr(),
                              helperMaxLines: 2,
                              errorText: remoteCodeErrorText.value,
                              errorMaxLines: 2,
                              // Show refresh button if code expired
                              suffixIcon: remoteCodeExpired.value && !remoteCodeLoading.value
                                  ? IconButton(
                                      icon: const Icon(Icons.refresh),
                                      color: Theme.of(context).colorScheme.primary,
                                      tooltip: 'curator.sign_in_screen_button_request_new_code'.tr(),
                                      onPressed: () {
                                        initiateRemoteAccess();
                                      },
                                    )
                                  : null,
                              // Show loading indicator while requesting/validating code
                              suffix: remoteCodeLoading.value
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : null,
                            ),
                            autofillHints: [AutofillHints.oneTimeCode],
                            controller: remoteCodeController,
                            keyboardType: TextInputType.number,
                            textInputAction: TextInputAction.done,
                            focusNode: remoteCodeFocusNode,
                            enabled: !remoteCodeLoading.value && !loggingIn.value,
                            autovalidateMode: AutovalidateMode.onUserInteraction,
                          ),
                        ],
                      )
                    : const SizedBox.shrink(),
              ),
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
                        ? LoadingIcon(key: const ValueKey("loading"), text: 'curator.login_form_loading_text'.tr())
                        : AnimatedBuilder(
                            animation: Listenable.merge([
                              emailController,
                              passwordController,
                              // serverEndpointController,
                              hasPreviousLoginFailed,
                            ]),
                            builder: (_, __) {
                              final canSubmit = areRequiredFieldsFilled() && !hasPreviousLoginFailed.value;
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
          context.isDarkTheme ? 'assets/curator-photos-logo-dark.svg' : 'assets/curator-photos-logo-light.svg',
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
                  children: [buildLogo(context), const SizedBox(height: 24.0), buildLoginForm()],
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
