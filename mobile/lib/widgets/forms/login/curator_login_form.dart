import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:flutter_svg/svg.dart';
import 'package:homecloud_frontend/api/remote_access.swagger.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/developer_options.provider.dart';
import 'package:immich_mobile/providers/device_path_refresh.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
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
import 'package:immich_mobile/widgets/forms/login/remote_code_dialog.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';
import 'package:package_info_plus/package_info_plus.dart';

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

    final discovery = ref.read(deviceDiscoveryProvider);
    final devices = useState<List<DeviceItem>>([]);
    final staticDevice = useState<DeviceItem?>(null);
    final selectedDevice = useState<DeviceItem?>(null);
    final isDiscovering = useState<bool>(false);

    final isRemoteCodeModalActive = useRef(false);

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
        email.value.isNotEmpty && passwordController.text.isNotEmpty && selectedDevice.value?.baseUrl != null;

    List<DeviceItem> mergeDevices(List<DeviceItem> existing, List<DeviceItem> incoming) {
      final merged = <String, DeviceItem>{};

      void addDevice(DeviceItem device) {
        final key = device.about?.certificateCommonName ?? device.baseUrl?.toString() ?? device.name;
        final existing = merged[key];
        if (existing == null) {
          merged[key] = device;
        } else {
          // Merge paths: prefer non-null/non-empty paths, combine if both have values
          final List<DevicePath>? mergedPaths;
          final existingPaths = existing.paths;
          final devicePaths = device.paths;

          if (existingPaths != null && existingPaths.isNotEmpty) {
            if (devicePaths != null && devicePaths.isNotEmpty) {
              // Both have paths - merge them
              mergedPaths = [...existingPaths, ...devicePaths];
            } else {
              // Only existing has paths
              mergedPaths = existingPaths;
            }
          } else if (devicePaths != null && devicePaths.isNotEmpty) {
            // Only device has paths
            mergedPaths = devicePaths;
          } else {
            // Both are null or empty - preserve null
            mergedPaths = null;
          }

          merged[key] = DeviceItem(
            baseUrl: existing.baseUrl,
            about: existing.about,
            status: existing.status,
            paths: mergedPaths,
          );
        }
      }

      for (final device in existing) {
        addDevice(device);
      }
      for (final device in incoming) {
        addDevice(device);
      }

      return merged.values.toList();
    }

    void handleCantFindDevice({required Future<void> Function() onStartDiscovery}) async {
      final isAuthenticated = ref.read(remoteProvider).isAuthenticated;
      if (isAuthenticated) {
        context.pushRoute(
          UnableToDetectRoute(
            onRetry: () {
              context.pop();
              onStartDiscovery();
            },
          ),
        );
      } else {
        final emailAddress = email.value;
        if (emailAddress.isEmpty) {
          warningMessage.value = 'login_form_err_invalid_email'.tr();
          return;
        }

        if (isRemoteCodeModalActive.value == true) return;

        isRemoteCodeModalActive.value = true;
        await showRemoteCodeModal(context: context, email: emailAddress, onSuccess: () async => onStartDiscovery());
        isRemoteCodeModalActive.value = false;
      }
    }

    preselectFavoriteDevice() {
      if (devices.value.isEmpty) return;

      final favoriteDeviceId = discovery.connectedDeviceID;

      DeviceItem? candidateDevice;
      if (favoriteDeviceId?.isNotEmpty == true) {
        candidateDevice = devices.value.firstWhereOrNull((d) => d.about?.certificateCommonName == favoriteDeviceId);
      }

      selectedDevice.value = candidateDevice ?? devices.value.firstOrNull;
    }

    Future<void> startDiscovery() async {
      if (isDiscovering.value) {
        return;
      }

      isDiscovering.value = true;
      devices.value = [];

      try {
        final isAuthenticated = ref.read(remoteProvider).isAuthenticated;

        List<DeviceItem> mdnsDevices = [];
        List<DeviceItem> remoteDevices = [];

        if (isAuthenticated) {
          final result = await discovery.startDeviceDiscovery();
          mdnsDevices = result['mdnsDevices'] ?? <DeviceItem>[];
          remoteDevices = result['remoteDevices'] ?? <DeviceItem>[];
        } else {
          final result = await discovery.startMdnsDiscovery();
          mdnsDevices = result ?? [];
        }

        devices.value = mergeDevices(devices.value, [...mdnsDevices, ...remoteDevices]);

        if (devices.value.isNotEmpty) {
          preselectFavoriteDevice();
        } else {
          handleCantFindDevice(onStartDiscovery: startDiscovery);
          return;
        }
      } catch (error, stackTrace) {
        log.warning('Failed to discover devices', error, stackTrace);
      } finally {
        if (context.mounted) {
          isDiscovering.value = false;
        }
      }
    }

    useEffect(() {
      final devStaticDeviceUrl = ref.read(developerOptionsProvider).devStaticDeviceUrl;
      if (devStaticDeviceUrl != null) {
        final baseUrl = Uri.tryParse(devStaticDeviceUrl);
        staticDevice.value = DeviceItem(
          baseUrl: baseUrl,
          paths: [
            DevicePath(address: baseUrl?.host ?? devStaticDeviceUrl, port: baseUrl?.port, type: DevicePathType.local),
          ],
        );
        selectedDevice.value = staticDevice.value;
      }
      return null;
    }, []);

    useEffect(() {
      // Defer provider access until after build phase to avoid initialization conflicts
      WidgetsBinding.instance.addPostFrameCallback((_) {
        email.value = ref.read(deviceProvider).login;

        if (staticDevice.value != null) return;
        preselectFavoriteDevice();
        startDiscovery();
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

    void populateDevCredentials() async {
      const env = String.fromEnvironment('ENVIRONMENT', defaultValue: 'prod');
      await dotenv.load(fileName: '.env.$env');
      final emailValue = dotenv.env['DEV_EMAIL'];
      final password = dotenv.env['DEV_PASSWORD'];

      clearAllErrors();
      email.value = emailValue ?? '';
      passwordController.text = password ?? '';
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
      final device = selectedDevice.value;
      if (device == null) {
        warningMessage.value = "login_form_no_device_selected".tr();
        return false;
      }
      final baseUrl = device.baseUrl;
      if (baseUrl == null) {
        warningMessage.value = "login_form_server_empty".tr();
        return false;
      }
      final normalizedBaseUrl =
          '${baseUrl.scheme}://${baseUrl.host}${baseUrl.port != 80 && baseUrl.port != 443 ? ':${baseUrl.port}' : ''}/photos';

      clearAllErrors();
      final sanitizedServerUrl = sanitizeUrl(normalizedBaseUrl);
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
          context.pushRoute(
            UnableToConnectRoute(
              onRetry: () {
                context.pop();
                login();
              },
            ),
          );
          return;
        }

        invalidateAllApiRepositoryProviders(ref);

        final result = await ref.read(authProvider.notifier).login(email.value, passwordController.text);

        final device = selectedDevice.value;
        if (device != null) {
          if (device.about != null) {
            discovery.connectToDevice(device);
          } else {
            discovery.disconnectDevice();
          }

          final paths = device.paths;
          if (paths != null && paths.isNotEmpty) {
            await ref.read(devicePathRefreshServiceProvider).processAndSavePaths(paths);
          }
        }

        if (result.shouldChangePassword && !result.isAdmin) {
          context.pushRoute(const ChangePasswordRoute());
        } else {
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
        context.pushRoute(
          UnableToConnectRoute(
            onRetry: () {
              context.pop();
              login();
            },
          ),
        );
        warningMessage.value = "login_form_failed_login".tr();
        hasPreviousLoginFailed.value = true;
      } finally {
        isLoading.value = false;
      }
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Expanded(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              GestureDetector(
                onDoubleTap: () => populateDevCredentials(),
                child: Column(
                  children: [
                    const Image(width: 140.0, height: 140.0, image: AssetImage('assets/curator-photos-logo.png')),
                    SvgPicture.asset(
                      context.isDarkTheme
                          ? 'assets/curator-photos-logo-dark.svg'
                          : 'assets/curator-photos-logo-light.svg',
                      height: 20,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 24.0),
              isLoading.value
                  ? LoadingIcon(key: const ValueKey("loading"), text: 'curator.login_form_loading_text'.tr())
                  : Form(
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
                            DeviceSelector(
                              controller: deviceController,
                              devices: staticDevice.value != null
                                  ? [...devices.value, staticDevice.value]
                                  : devices.value,
                              selectedDevice: selectedDevice.value,
                              isDetecting: isDiscovering.value,
                              focusNode: deviceFocusNode,
                              enabled: !isLoading.value,
                              onDeviceSelected: (device) {
                                if (device is DeviceItem) {
                                  selectedDevice.value = device;
                                  // devices.value = mergeDevices(devices.value, [device]);
                                } else {
                                  selectedDevice.value = null;
                                }
                                fieldFocusChange(context, deviceFocusNode, passwordFocusNode);
                              },
                              onRefresh: startDiscovery,
                            ),
                            const SizedBox(height: 4.0),
                            GestureDetector(
                              onTap: () => handleCantFindDevice(onStartDiscovery: startDiscovery),
                              child: Padding(
                                padding: const EdgeInsets.all(10.0),
                                child: Text(
                                  "curator.login_form_cant_find_device".tr(),
                                  style: TextStyle(
                                    color: Theme.of(context).primaryColor,
                                    fontSize: 14.0,
                                    fontWeight: FontWeight.w500,
                                  ),
                                ),
                              ),
                            ),
                            const SizedBox(height: 24.0),
                            PasswordInput(
                              controller: passwordController,
                              focusNode: passwordFocusNode,
                              onSubmit: login,
                              hasExternalError: hasPasswordError.value,
                            ),
                            const SizedBox(height: 4.0),
                            GestureDetector(
                              child: Padding(
                                padding: const EdgeInsets.all(10.0),
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
                          ],
                        ),
                      ),
                    ),
            ],
          ),
        ),
        isLoading.value
            ? const SizedBox.shrink()
            : AnimatedBuilder(
                animation: Listenable.merge([passwordController, hasPreviousLoginFailed]),
                builder: (_, __) {
                  final canSubmit = areRequiredFieldsFilled() && !hasPreviousLoginFailed.value;
                  return LoginButton(onPressed: login, withIcon: false, isDisabled: !canSubmit);
                },
              ),
      ],
    );
  }
}
