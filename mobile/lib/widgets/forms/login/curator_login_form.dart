import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:flutter_svg/svg.dart';
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
import 'package:immich_mobile/widgets/common/network_status_snackbar.widget.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:immich_mobile/utils/env_config.dart';
import 'package:hc_device/api/api.enums.swagger.dart' as hc_api_enums;

import 'package:hc_device/hc_device.dart';

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
    final isResetPasswordLoading = useState<bool>(false);
    final hasPreviousLoginFailed = useState<bool>(false);

    final warningMessage = useState<String?>(null);
    final hasEmailError = useState<bool>(false);
    final hasPasswordError = useState<bool>(false);

    final formKey = useMemoized<GlobalKey<FormState>>(() => GlobalKey<FormState>());

    final serverInfo = ref.watch(serverInfoProvider);

    final devices = useState<List<DeviceItem>>([]);
    final staticDevice = useState<DeviceItem?>(null);
    final selectedDevice = useState<DeviceItem?>(null);
    final isDiscovering = useState<bool>(false);
    final isRemoteCodeModalActive = useRef(false);
    final shouldRetryDiscoveryAfterOtp = useState<bool>(false);

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

    bool isDeviceSelectionValid(DeviceItem? d) {
      if (d == null) return false;
      if (d.baseUrl != null) return true;
      if (d.about != null) return true;
      return d.remoteDevice != null;
    }

    bool areRequiredFieldsFilled() =>
        email.value.isNotEmpty && passwordController.text.isNotEmpty && isDeviceSelectionValid(selectedDevice.value);

    String? validateEmail(String emailAddress) {
      final simpleEmailPattern = RegExp(r'^[^@]+@[^@]+\.[^@]+$');
      if (!simpleEmailPattern.hasMatch(emailAddress)) {
        return 'login_form_err_invalid_email'.tr();
      }
      return null;
    }

    void handleCantFindDeviceManually({required Future<void> Function() onStartDiscovery}) async {
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
        await showRemoteCodeModal(
          context: context,
          initiate: ref.read(remoteAuthProvider).initiate,
          email: emailAddress,
          skipInitialCodeSend: ref.read(remoteProvider).isAuthenticated,
          onSuccess: () async => onStartDiscovery(),
        );
        isRemoteCodeModalActive.value = false;
      }
    }

    Future<void> handleAutoOtpAfterMdnsFailure({
      required Future<void> Function() onStartDiscovery,
      required bool hasMdnsDevices,
    }) async {
      final isAuthenticated = ref.read(remoteProvider).isAuthenticated;
      // Auto OTP is allowed only when mDNS did not find any device and
      // Remote Access is not authenticated yet.
      if (hasMdnsDevices || isAuthenticated) {
        return;
      }

      final emailAddress = email.value;
      if (emailAddress.isEmpty) {
        warningMessage.value = 'login_form_err_invalid_email'.tr();
        return;
      }

      if (isRemoteCodeModalActive.value == true) return;
      isRemoteCodeModalActive.value = true;
      await showRemoteCodeModal(
        context: context,
        initiate: ref.read(remoteAuthProvider).initiate,
        email: emailAddress,
        skipInitialCodeSend: ref.read(remoteProvider).isAuthenticated,
        onSuccess: () async {
          // If discovery is already running, defer restart until it fully completes.
          if (isDiscovering.value) {
            shouldRetryDiscoveryAfterOtp.value = true;
            return;
          }
          await onStartDiscovery();
        },
      );
      isRemoteCodeModalActive.value = false;
    }

    preselectFavoriteDevice() {
      if (devices.value.isEmpty) return;

      final favoriteDeviceId = ref.read(deviceProvider).deviceID;

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
        final dp = ref.read(deviceProvider);
        final rp = ref.read(remoteProvider);
        final completer = Completer<void>();
        final found = <DeviceItem>[];
        late DeviceDetectionService detection;
        detection = DeviceDetectionService(
          deviceProvider: dp,
          remoteProvider: rp,
          onDeviceFound: (d) => found.add(d),
          onDetectionComplete: (_) {
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
          onError: (_, __) {
            if (!completer.isCompleted) {
              completer.complete();
            }
          },
        );
        await detection.startDetection();
        try {
          await completer.future.timeout(const Duration(seconds: 45));
        } on TimeoutException {
          await detection.cancelDetection();
        }

        final mdnsDevices = found.where((d) => d.debugHostType == 'mDNS').toList();
        final remoteDevices = found.where((d) => d.debugHostType != 'mDNS').toList();
        log.info('[MDNS discovery]: devices found ${mdnsDevices.length}');
        log.info('[Remote discovery]: devices found ${remoteDevices.length}');

        devices.value = mergeDiscoveredDevices(devices.value, [...mdnsDevices, ...remoteDevices]);

        if (devices.value.isNotEmpty) {
          preselectFavoriteDevice();
        } else {
          await handleAutoOtpAfterMdnsFailure(onStartDiscovery: startDiscovery, hasMdnsDevices: mdnsDevices.isNotEmpty);
          return;
        }
      } catch (error, stackTrace) {
        log.warning('Failed to discover devices', error, stackTrace);
      } finally {
        if (context.mounted) {
          isDiscovering.value = false;
          if (shouldRetryDiscoveryAfterOtp.value) {
            shouldRetryDiscoveryAfterOtp.value = false;
            // Run a fresh discovery pass after OTP success once the previous run is done.
            unawaited(startDiscovery());
          }
        }
      }
    }

    useEffect(() {
      final devStaticDeviceUrl = ref.read(developerOptionsProvider).devStaticDeviceUrl;
      if (devStaticDeviceUrl != null) {
        final baseUrl = Uri.tryParse(devStaticDeviceUrl);
        staticDevice.value = DeviceItem(hostname: devStaticDeviceUrl, baseUrl: baseUrl, debugHostType: 'static');
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
      if (EnvConfig.environment != AppEnvironment.dev) return;
      final emailValue = await EnvConfig.get(EnvKey.devEmail);
      final password = await EnvConfig.get(EnvKey.devPassword);

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
      log.info(
        '[ResetPassword] Validating server settings for selected device: '
        'id=${device?.id}, host=${device?.baseUrl}, pathType=${device?.debugHostType}',
      );
      if (device == null) {
        warningMessage.value = "login_form_no_device_selected".tr();
        log.warning('[ResetPassword] Aborted: no selected device');
        return false;
      }
      final baseUrl = device.baseUrl;
      if (baseUrl == null) {
        warningMessage.value = "login_form_server_empty".tr();
        log.warning('[ResetPassword] Aborted: selected device has no baseUrl');
        return false;
      }
      final normalizedBaseUrl =
          '${baseUrl.scheme}://${baseUrl.host}${baseUrl.port != 80 && baseUrl.port != 443 ? ':${baseUrl.port}' : ''}/photos';

      clearAllErrors();
      final sanitizedServerUrl = sanitizeUrl(normalizedBaseUrl);
      final normalizedServerUrl = punycodeEncodeUrl(sanitizedServerUrl);

      if (normalizedServerUrl.isEmpty) {
        warningMessage.value = "login_form_server_empty".tr();
        log.warning('[ResetPassword] Aborted: normalized server url is empty');
        return false;
      }

      try {
        await ref.read(authProvider.notifier).validateServerUrl(normalizedServerUrl);

        await ref.read(serverInfoProvider.notifier).getServerInfo();
        await updateVersionCompatibilityWarning();

        log.info('[ResetPassword] Server validation succeeded: $normalizedServerUrl');
        return true;
      } on ApiException catch (e) {
        warningMessage.value = e.message ?? 'login_form_api_exception'.tr();
        log.warning('[ResetPassword] Server validation failed with ApiException: code=${e.code}, message=${e.message}');
        return false;
      } on HandshakeException {
        warningMessage.value = 'login_form_handshake_exception'.tr();
        log.warning('[ResetPassword] Server validation failed with TLS/handshake exception');
        return false;
      } catch (e) {
        warningMessage.value = 'login_form_server_error'.tr();
        log.warning('[ResetPassword] Server validation failed with unexpected error: $e');
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

    Future<bool> prepareDeviceHostForResetPassword() async {
      final device = selectedDevice.value;
      if (device == null || !isDeviceSelectionValid(device)) {
        warningMessage.value = "login_form_no_device_selected".tr();
        log.warning('[ResetPassword] Aborted: invalid device selection');
        return false;
      }
      log.info(
        '[ResetPassword] Preparing device host: '
        'id=${device.id}, baseUrl=${device.baseUrl}, pathType=${device.debugHostType}',
      );

      final dp = ref.read(deviceProvider);
      final rp = ref.read(remoteProvider);
      final detection = DeviceDetectionService(deviceProvider: dp, remoteProvider: rp);

      if (device.about != null && device.baseUrl != null) {
        await dp.setHost(
          baseUrl: device.baseUrl,
          deviceID: device.id,
          seagateDeviceID: device.remoteDevice?.seagateDeviceID,
          debugHostType: device.debugHostType,
        );
        log.info('[ResetPassword] Using direct device host: ${device.baseUrl}');
        return true;
      }

      final seagateDeviceID = device.remoteDevice?.seagateDeviceID;
      if (seagateDeviceID == null || seagateDeviceID.isEmpty) {
        warningMessage.value = "login_form_server_error".tr();
        log.warning('[ResetPassword] Aborted: missing seagateDeviceID for remote-only device');
        return false;
      }

      final ping = await detection.findOptimalDeviceConnection(device: device, seagateDeviceID: seagateDeviceID);
      if (!ping.success || ping.baseUrl == null) {
        warningMessage.value = "login_form_server_error".tr();
        log.warning(
          '[ResetPassword] Failed to resolve optimal device path: '
          'success=${ping.success}, baseUrl=${ping.baseUrl}, debugHostType=${ping.debugHostType}',
        );
        return false;
      }

      await dp.setHost(
        baseUrl: ping.baseUrl,
        deviceID: device.id,
        seagateDeviceID: seagateDeviceID,
        debugHostType: ping.debugHostType,
        devicePaths: dp.getCachedDevicePaths()?.paths,
      );
      log.info('[ResetPassword] Device host prepared via optimal path: ${ping.baseUrl}');
      return true;
    }

    Future<bool> checkDeviceReadyForResetPassword() async {
      try {
        final response = await ref.read(deviceProvider).api.statusGet();
        if (!response.isSuccessful) {
          warningMessage.value = 'login_form_server_error'.tr();
          log.warning(
            '[ResetPassword] Device readiness check failed: '
            'status=${response.statusCode}, error=${response.error}',
          );
          return false;
        }
        final status = response.body;
        if (status == null) {
          warningMessage.value = 'login_form_server_error'.tr();
          log.warning('[ResetPassword] Device readiness check failed: empty status payload');
          return false;
        }
        if (status.oobe.done == false || status.systemState != hc_api_enums.State.ready) {
          warningMessage.value = 'login_form_server_error'.tr();
          log.warning(
            '[ResetPassword] Device not ready: oobeDone=${status.oobe.done}, systemState=${status.systemState}',
          );
          return false;
        }
        log.info('[ResetPassword] Device readiness check succeeded');
        return true;
      } catch (error, stackTrace) {
        log.warning('Failed to validate device readiness before reset', error, stackTrace);
        warningMessage.value = 'login_form_server_error'.tr();
        return false;
      }
    }

    bool isResetPasswordEnabled() =>
        !isLoading.value &&
        !isResetPasswordLoading.value &&
        email.value.isNotEmpty &&
        validateEmail(email.value) == null &&
        isDeviceSelectionValid(selectedDevice.value);

    DeviceItem? resolveSelectedDeviceForAction() {
      final selected = selectedDevice.value;
      final selectedId = selected?.id;
      if (selectedId != null && selectedId != 'unknown_id') {
        final matchedById = devices.value.firstWhereOrNull((device) => device.id == selectedId);
        if (matchedById != null && matchedById != selected) {
          log.info(
            '[ResetPassword] Syncing selected device by stable id: '
            'id=$selectedId, previous=${selected?.baseUrl}, resolved=${matchedById.baseUrl}',
          );
          selectedDevice.value = matchedById;
        }
        if (matchedById != null) {
          return selectedDevice.value;
        }
      }

      final inputName = deviceController.text.trim();
      if (inputName.isEmpty) {
        return selected;
      }

      final matchedByName = devices.value.where(
        (device) => device.name.trim().toLowerCase() == inputName.toLowerCase(),
      ).toList();
      if (matchedByName.length != 1) {
        return selected;
      }
      final resolvedByName = matchedByName.first;

      if (selected != resolvedByName) {
        log.info(
          '[ResetPassword] Syncing selected device from input: '
          'input="$inputName", previous=${selected?.id}, resolved=${resolvedByName.id}',
        );
        selectedDevice.value = resolvedByName;
      }
      return selectedDevice.value;
    }

    Future<void> handleResetPassword() async {
      log.info('[ResetPassword] Triggered from login form');
      final effectiveSelectedDevice = resolveSelectedDeviceForAction();
      if (!isResetPasswordEnabled()) {
        if (email.value.isNotEmpty && validateEmail(email.value) != null) {
          warningMessage.value = 'login_form_err_invalid_email'.tr();
        } else if (!isDeviceSelectionValid(effectiveSelectedDevice)) {
          warningMessage.value = "login_form_no_device_selected".tr();
        }
        return;
      }

      clearAllErrors();
      isResetPasswordLoading.value = true;

      try {
        final canPrepareDeviceHost = await prepareDeviceHostForResetPassword();
        if (!canPrepareDeviceHost) {
          return;
        }

        final isDeviceReady = await checkDeviceReadyForResetPassword();
        if (!isDeviceReady) {
          return;
        }

        await ref.read(authProvider.notifier).requestPasswordReset(email.value);
        log.info('[ResetPassword] Request sent successfully for email=${email.value.trim()}');
        if (context.mounted) {
          final trimmedEmail = email.value.trim();
          final messenger = ScaffoldMessenger.of(context);
          messenger.hideCurrentSnackBar();
          messenger.showSnackBar(
            SnackBar(
              behavior: SnackBarBehavior.floating,
              backgroundColor: Colors.transparent,
              elevation: 0,
              margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
              padding: EdgeInsets.zero,
              duration: const Duration(seconds: 4),
              content: NetworkStatusSnackBar(
                message: '${'password_reset_success'.tr()}: $trimmedEmail',
                onClose: messenger.hideCurrentSnackBar,
              ),
            ),
          );
        }
      } on ApiException catch (error) {
        warningMessage.value = 'errors.unable.to.reset.password'.tr();
        log.warning('[ResetPassword] API failed: code=${error.code}, message=${error.message}');
      } catch (error, stackTrace) {
        log.warning('Failed to reset password', error, stackTrace);
        warningMessage.value = 'errors.unable.to.reset.password'.tr();
      } finally {
        isResetPasswordLoading.value = false;
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
          final dp = ref.read(deviceProvider);
          final rp = ref.read(remoteProvider);
          final detection = DeviceDetectionService(deviceProvider: dp, remoteProvider: rp);
          if (device.about != null && device.baseUrl != null) {
            await dp.setHost(
              baseUrl: device.baseUrl,
              deviceID: device.id,
              seagateDeviceID: device.remoteDevice?.seagateDeviceID,
              debugHostType: device.debugHostType,
            );
          } else if (device.remoteDevice != null) {
            final ping = await detection.findOptimalDeviceConnection(
              device: device,
              seagateDeviceID: device.remoteDevice!.seagateDeviceID,
            );
            if (ping.success && ping.baseUrl != null) {
              await dp.setHost(
                baseUrl: ping.baseUrl,
                deviceID: device.id,
                seagateDeviceID: device.remoteDevice?.seagateDeviceID,
                debugHostType: ping.debugHostType,
                devicePaths: dp.getCachedDevicePaths()?.paths,
              );
            } else {
              dp.clearDevice(save: true);
            }
          } else {
            dp.clearDevice(save: true);
          }

          final paths = dp.devicePaths ?? dp.getCachedDevicePaths()?.paths;
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
        if (e.code == 400 || e.code == 401 || e.code == 403) {
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
                              onTap: () => handleCantFindDeviceManually(onStartDiscovery: startDiscovery),
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
                            isResetPasswordLoading.value
                                ? const Padding(
                                    padding: EdgeInsets.all(10.0),
                                    child: Align(
                                      alignment: Alignment.centerLeft,
                                      child: SizedBox(
                                        height: 20.0,
                                        width: 20.0,
                                        child: CircularProgressIndicator.adaptive(strokeWidth: 2.0),
                                      ),
                                    ),
                                  )
                                : GestureDetector(
                                    onTap: isResetPasswordEnabled() ? handleResetPassword : null,
                                    child: Padding(
                                      padding: const EdgeInsets.all(10.0),
                                      child: Text(
                                        'reset_password'.tr(),
                                        style: TextStyle(
                                          color: isResetPasswordEnabled()
                                              ? Theme.of(context).primaryColor
                                              : Theme.of(context).disabledColor,
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
