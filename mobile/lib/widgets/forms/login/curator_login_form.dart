import 'dart:async';
import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:collection/collection.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/app_life_cycle.provider.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/developer_options.provider.dart';
import 'package:immich_mobile/providers/device_path_refresh.provider.dart';
import 'package:immich_mobile/providers/gallery_permission.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/network/local_network_permission_otp_gate.dart';
import 'package:immich_mobile/services/network/recovery/recovery_policy.dart';
import 'package:immich_mobile/utils/env_config.dart';
import 'package:immich_mobile/utils/provider_utils.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:immich_mobile/utils/version_compatibility.dart';
import 'package:immich_mobile/widgets/forms/login/device_selector.dart';
import 'package:immich_mobile/widgets/forms/login/loading_icon.dart';
import 'package:immich_mobile/widgets/forms/login/login_brand_header.dart';
import 'package:immich_mobile/widgets/forms/login/login_button.dart';
import 'package:immich_mobile/widgets/forms/login/password_input.dart';
import 'package:immich_mobile/widgets/forms/login/remote_code_dialog.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'package:hc_device/api/remote_access.enums.swagger.dart' show DevicePathType;
import 'package:hc_device/hc_device.dart';

class CuratorLoginForm extends HookConsumerWidget {
  final log = Logger('LoginForm');
  final void Function(String? initialEmailErrorMessage) switchToRemoteAccessForm;

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
    final isCantFindDeviceLoading = useState<bool>(false);
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
    // iOS: OTP was deferred while the OS Local Network permission dialog was up.
    final pendingDiscoveryAfterLocalNetPermission = useRef(false);
    final activeDetection = useRef<DeviceDetectionService?>(null);
    final isFormActive = useRef(true);

    bool isAppLifecycleBlockingUi() {
      final state = ref.read(appStateProvider);
      return state == AppLifeCycleEnum.inactive ||
          state == AppLifeCycleEnum.paused ||
          state == AppLifeCycleEnum.hidden ||
          state == AppLifeCycleEnum.detached;
    }

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
        isCantFindDeviceLoading.value = true;
        try {
          await showRemoteCodeModal(
            context: context,
            remoteProvider: ref.read(remoteProvider.notifier),
            email: emailAddress,
            skipInitialCodeSend: ref.read(remoteProvider).isAuthenticated,
            onDialogPresented: () {
              isCantFindDeviceLoading.value = false;
            },
            onEmailNotAllowed: () {
              hasEmailError.value = true;
              final errorMessage = 'curator.email_not_registered_error'.tr();
              warningMessage.value = errorMessage;
              switchToRemoteAccessForm(errorMessage);
            },
            onSuccess: () async {
              // Always refresh discovery after OTP succeeds.
              // If detection is active, queue exactly one restart.
              if (isDiscovering.value) {
                shouldRetryDiscoveryAfterOtp.value = true;
                return;
              }
              await onStartDiscovery();
            },
          );
        } finally {
          isCantFindDeviceLoading.value = false;
          isRemoteCodeModalActive.value = false;
        }
      }
    }

    Future<void> handleAutoOtpAfterMdnsFailure({
      required Future<void> Function() onStartDiscovery,
      required bool hasMdnsDevices,
    }) async {
      final isAuthenticated = ref.read(remoteProvider).isAuthenticated;
      final emailAddress = email.value;
      if (!RecoveryPolicy.shouldPromptLoginOtp(
        hasMdnsDevices: hasMdnsDevices,
        remoteAuth: isAuthenticated,
        hasEmail: emailAddress.isNotEmpty,
        otpModalShowing: isRemoteCodeModalActive.value == true,
      )) {
        if (!hasMdnsDevices && !isAuthenticated && emailAddress.isEmpty) {
          warningMessage.value = 'login_form_err_invalid_email'.tr();
        }
        return;
      }

      // Same gate as network_monitor: do not open Remote Access under the OS
      // Local Network permission dialog. Retry discovery once the user answers.
      if (await shouldDeferRemoteAccessOtpForLocalNetPermission(
        isIos: Platform.isIOS,
        remoteAuthenticated: isAuthenticated,
        isAppBlockingUi: isAppLifecycleBlockingUi,
      )) {
        pendingDiscoveryAfterLocalNetPermission.value = true;
        log.info(
          '[MDNS discovery]: OTP deferred: app inactive '
          '(likely OS Local Network permission dialog)',
        );
        return;
      }

      isRemoteCodeModalActive.value = true;
      await showRemoteCodeModal(
        context: context,
        remoteProvider: ref.read(remoteProvider.notifier),
        email: emailAddress,
        skipInitialCodeSend: ref.read(remoteProvider).isAuthenticated,
        onEmailNotAllowed: () {
          hasEmailError.value = true;
          final errorMessage = 'curator.email_not_registered_error'.tr();
          warningMessage.value = errorMessage;
          switchToRemoteAccessForm(errorMessage);
        },
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

      final deviceState = ref.read(deviceProvider);
      // Prefer the currently favorite device, then the last device the user
      // connected to (survives logout), and fall back to the first in the list.
      final preferredDeviceId = deviceState.deviceID?.isNotEmpty == true ? deviceState.deviceID : deviceState.lastDeviceID;

      DeviceItem? candidateDevice;
      if (preferredDeviceId?.isNotEmpty == true) {
        // Match by [DeviceItem.id] — the same value persisted on connect via
        // setHost(deviceID: device.id). It resolves through remoteDevice first,
        // so matching only on about?.certificateCommonName misses remote devices.
        candidateDevice = devices.value.firstWhereOrNull((d) => d.id == preferredDeviceId);
      }

      selectedDevice.value = candidateDevice ?? devices.value.firstOrNull;
    }

    Future<void> startDiscovery() async {
      if (!isFormActive.value) {
        return;
      }
      if (isDiscovering.value) {
        return;
      }

      isDiscovering.value = true;
      devices.value = [];

      try {
        final dp = ref.read(deviceProvider.notifier);
        final rp = ref.read(remoteProvider.notifier);
        final completer = Completer<void>();
        final found = <DeviceItem>[];
        await activeDetection.value?.cancelDetection();
        final detection = DeviceDetectionService(
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
        activeDetection.value = detection;
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
        activeDetection.value = null;
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
        email.value = ref.read(deviceProvider).login ?? '';

        if (staticDevice.value != null) return;
        preselectFavoriteDevice();
        startDiscovery();
      });
      return null;
    }, []);

    ref.listen<AppLifeCycleEnum>(appStateProvider, (previous, next) {
      if (!isFormActive.value) {
        return;
      }
      if (next != AppLifeCycleEnum.resumed && next != AppLifeCycleEnum.active) {
        return;
      }
      if (!pendingDiscoveryAfterLocalNetPermission.value) {
        return;
      }
      pendingDiscoveryAfterLocalNetPermission.value = false;
      log.info('[MDNS discovery]: retrying after Local Network permission decision');
      unawaited(startDiscovery());
    });

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
        isFormActive.value = false;
        final detection = activeDetection.value;
        activeDetection.value = null;
        if (detection != null) {
          unawaited(detection.cancelDetection());
        }
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

    Future<PingResult?> resolveRemoteDeviceConnection({
      required DeviceItem device,
      required String flowTag,
      bool requireFreshPaths = false,
    }) async {
      final seagateDeviceID = device.remoteDevice?.seagateDeviceID;
      if (seagateDeviceID == null || seagateDeviceID.isEmpty) {
        warningMessage.value = "login_form_server_error".tr();
        log.warning('[$flowTag] Aborted: missing seagateDeviceID for remote-only selected device');
        return null;
      }

      final detection = DeviceDetectionService(
        deviceProvider: ref.read(deviceProvider.notifier),
        remoteProvider: ref.read(remoteProvider.notifier),
      );
      final ping = await detection.findOptimalDeviceConnection(
        device: device,
        seagateDeviceID: seagateDeviceID,
        useCachedPaths: !requireFreshPaths,
      );
      if (!ping.success || ping.baseUrl == null) {
        warningMessage.value = "login_form_server_error".tr();
        log.warning(
          '[$flowTag] Failed to resolve selected remote device path: '
          'success=${ping.success}, baseUrl=${ping.baseUrl}, debugHostType=${ping.debugHostType}',
        );
        return null;
      }

      return ping;
    }

    DeviceItem? resolveSelectedDeviceForAction() {
      final selected = selectedDevice.value;
      final selectedId = selected?.id;
      if (selectedId != null && selectedId != 'unknown_id') {
        final matchedById = devices.value.firstWhereOrNull((device) => device.id == selectedId);
        if (matchedById != null && matchedById != selected) {
          log.info(
            '[LoginForm] Syncing selected device by stable id: '
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

      final matchedByName = devices.value
          .where((device) => device.name.trim().toLowerCase() == inputName.toLowerCase())
          .toList();
      if (matchedByName.length != 1) {
        return selected;
      }
      final resolvedByName = matchedByName.first;

      if (selected != resolvedByName) {
        log.info(
          '[LoginForm] Syncing selected device from input: '
          'input="$inputName", previous=${selected?.id}, resolved=${resolvedByName.id}',
        );
        selectedDevice.value = resolvedByName;
      }
      return selectedDevice.value;
    }

    String buildDevicePhotosBaseUrl(Uri baseUrl) {
      final hasCustomPort = baseUrl.port != 80 && baseUrl.port != 443;
      final authority = hasCustomPort ? '${baseUrl.host}:${baseUrl.port}' : baseUrl.host;
      return '${baseUrl.scheme}://$authority/photos';
    }

    Future<bool> syncServerEndpointWithBaseUrl({
      required Uri baseUrl,
      required String flowTag,
      DevicePathType? pathType,
    }) async {
      final normalizedBaseUrl = buildDevicePhotosBaseUrl(baseUrl);
      final sanitizedServerUrl = sanitizeUrl(normalizedBaseUrl);
      final normalizedServerUrl = punycodeEncodeUrl(sanitizedServerUrl);

      if (normalizedServerUrl.isEmpty) {
        warningMessage.value = "login_form_server_empty".tr();
        log.warning('[$flowTag] Aborted: normalized server url is empty');
        return false;
      }

      try {
        await ref.read(authProvider.notifier).validateServerUrl(normalizedServerUrl, pathType: pathType);
        log.info(
          '[$flowTag] Endpoint synced to selected device: $normalizedServerUrl '
          'pathType=${pathType?.value ?? '-'}',
        );
        return true;
      } on ApiException catch (e) {
        warningMessage.value = e.message ?? 'login_form_api_exception'.tr();
        log.warning('[$flowTag] Endpoint sync failed with ApiException: code=${e.code}, message=${e.message}');
        return false;
      } on HandshakeException {
        warningMessage.value = 'login_form_handshake_exception'.tr();
        log.warning('[$flowTag] Endpoint sync failed with TLS/handshake exception');
        return false;
      } catch (e) {
        warningMessage.value = 'login_form_server_error'.tr();
        log.warning('[$flowTag] Endpoint sync failed with unexpected error: $e');
        return false;
      }
    }

    Future<bool> fetchServerAuthSettings() async {
      final device = resolveSelectedDeviceForAction();
      log.info(
        '[Login] Validating server settings for selected device: '
        'id=${device?.id}, host=${device?.baseUrl}, pathType=${device?.debugHostType}',
      );
      if (device == null) {
        warningMessage.value = "login_form_no_device_selected".tr();
        log.warning('[Login] Aborted: no selected device');
        return false;
      }

      // For Remote Access-capable devices, always resolve through path probing
      // so login validation uses the same priority model (local > public > remote).
      if (device.remoteDevice?.seagateDeviceID case final String seagateId when seagateId.isNotEmpty) {
        final ping = await resolveRemoteDeviceConnection(
          device: device,
          flowTag: 'Login',
          requireFreshPaths: true,
        );
        if (ping == null || ping.baseUrl == null) {
          return false;
        }
        final endpointSynced = await syncServerEndpointWithBaseUrl(
          baseUrl: ping.baseUrl!,
          flowTag: 'Login',
          pathType: ping.pathType,
        );
        if (!endpointSynced) {
          return false;
        }

        try {
          await ref.read(serverInfoProvider.notifier).getServerInfo();
          await updateVersionCompatibilityWarning();
          log.info(
            '[Login] Server validation succeeded via resolved path type=${ping.pathType?.name} '
            'host=${ping.baseUrl?.host}',
          );
          return true;
        } on ApiException catch (e) {
          warningMessage.value = e.message ?? 'login_form_api_exception'.tr();
          log.warning('[Login] Server validation failed with ApiException: code=${e.code}, message=${e.message}');
          return false;
        } on HandshakeException {
          warningMessage.value = 'login_form_handshake_exception'.tr();
          log.warning('[Login] Server validation failed with TLS/handshake exception');
          return false;
        } catch (e) {
          warningMessage.value = 'login_form_server_error'.tr();
          log.warning('[Login] Server validation failed with unexpected error: $e');
          return false;
        }
      }

      var baseUrl = device.baseUrl;
      var selectedPathType = device.pathType;
      if (baseUrl == null && device.remoteDevice != null) {
        final ping = await resolveRemoteDeviceConnection(device: device, flowTag: 'Login', requireFreshPaths: true);
        if (ping == null) {
          return false;
        }
        baseUrl = ping.baseUrl;
        selectedPathType = ping.pathType;
      }

      if (baseUrl == null) {
        warningMessage.value = "login_form_server_empty".tr();
        log.warning('[Login] Aborted: selected device has no baseUrl');
        return false;
      }

      clearAllErrors();
      final endpointSynced = await syncServerEndpointWithBaseUrl(
        baseUrl: baseUrl,
        flowTag: 'Login',
        pathType: selectedPathType,
      );
      if (!endpointSynced) {
        return false;
      }

      try {
        await ref.read(serverInfoProvider.notifier).getServerInfo();
        await updateVersionCompatibilityWarning();

        log.info('[Login] Server validation succeeded for selected device host=${baseUrl.host}');
        return true;
      } on ApiException catch (e) {
        warningMessage.value = e.message ?? 'login_form_api_exception'.tr();
        log.warning('[Login] Server validation failed with ApiException: code=${e.code}, message=${e.message}');
        return false;
      } on HandshakeException {
        warningMessage.value = 'login_form_handshake_exception'.tr();
        log.warning('[Login] Server validation failed with TLS/handshake exception');
        return false;
      } catch (e) {
        warningMessage.value = 'login_form_server_error'.tr();
        log.warning('[Login] Server validation failed with unexpected error: $e');
        return false;
      }
    }

    Future<bool> prepareDeviceHostForResetPassword() async {
      final device = resolveSelectedDeviceForAction();
      if (device == null || !isDeviceSelectionValid(device)) {
        warningMessage.value = "login_form_no_device_selected".tr();
        log.warning('[ResetPassword] Aborted: invalid device selection');
        return false;
      }
      log.info(
        '[ResetPassword] Preparing device host: '
        'id=${device.id}, baseUrl=${device.baseUrl}, pathType=${device.debugHostType}',
      );

      final dp = ref.read(deviceProvider.notifier);

      if (device.about != null && device.baseUrl != null) {
        await dp.setHost(
          baseUrl: device.baseUrl,
          deviceID: device.id,
          seagateDeviceID: device.remoteDevice?.seagateDeviceID,
          debugHostType: device.debugHostType,
          login: email.value.trim(),
        );
        log.info('[ResetPassword] Using direct device host: ${device.baseUrl}');
        return true;
      }

      final ping = await resolveRemoteDeviceConnection(
        device: device,
        flowTag: 'ResetPassword',
        requireFreshPaths: true,
      );
      if (ping == null || ping.baseUrl == null) {
        return false;
      }

      await dp.setHost(
        baseUrl: ping.baseUrl,
        deviceID: device.id,
        seagateDeviceID: device.remoteDevice?.seagateDeviceID,
        debugHostType: ping.debugHostType,
        login: email.value.trim(),
        devicePaths: device.remoteDevice?.seagateDeviceID == null
            ? null
            : dp.getCachedDevicePathsForDevice(device.remoteDevice!.seagateDeviceID)?.paths,
      );
      log.info('[ResetPassword] Device host prepared via optimal path: ${ping.baseUrl}');
      return true;
    }

    Future<bool> checkDeviceReadyForResetPassword() async {
      try {
        final response = await ref.read(deviceProvider.notifier).fetchStatus().timeout(const Duration(seconds: 30));
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
        final isOobeDone = status.oobe.done != false;
        final systemState = status.systemState.value;
        final isSystemReady = systemState == null || systemState == 'ready';
        if (!isOobeDone || !isSystemReady) {
          warningMessage.value = 'login_form_server_error'.tr();
          log.warning(
            '[ResetPassword] Device not ready: '
            'oobeDone=${status.oobe.done}, systemStateEnum=${status.systemState}, systemStateValue=$systemState',
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

    Future<bool> checkDeviceReadyForLogin() async {
      try {
        final response = await ref.read(deviceProvider.notifier).fetchStatus();
        if (!response.isSuccessful) {
          warningMessage.value = 'login_form_server_error'.tr();
          log.warning(
            '[Login] Device readiness check failed: '
            'status=${response.statusCode}, error=${response.error}',
          );
          return false;
        }
        final status = response.body;
        if (status == null) {
          warningMessage.value = 'login_form_server_error'.tr();
          log.warning('[Login] Device readiness check failed: empty status payload');
          return false;
        }
        final isOobeDone = status.oobe.done != false;
        final systemState = status.systemState.value;
        final isSystemReady = systemState == null || systemState == 'ready';
        if (!isOobeDone || !isSystemReady) {
          warningMessage.value = 'login_form_server_error'.tr();
          log.warning(
            '[Login] Device not ready: '
            'oobeDone=${status.oobe.done}, systemStateEnum=${status.systemState}, systemStateValue=$systemState',
          );
          return false;
        }
        log.info('[Login] Device readiness check succeeded');
        return true;
      } catch (error, stackTrace) {
        log.warning('Failed to validate device readiness before login', error, stackTrace);
        warningMessage.value = 'login_form_server_error'.tr();
        return false;
      }
    }

    /// Returns the prepared host's path type together with the outcome, so the
    /// endpoint sync that follows can record which kind of path won.
    Future<({bool prepared, DevicePathType? pathType})> prepareDeviceHostForLogin(DeviceItem device) async {
      final dp = ref.read(deviceProvider.notifier);
      final rp = ref.read(remoteProvider.notifier);
      final detection = DeviceDetectionService(deviceProvider: dp, remoteProvider: rp);
      final seagateDeviceId = device.remoteDevice?.seagateDeviceID;

      if (seagateDeviceId != null && seagateDeviceId.isNotEmpty) {
        final ping = await detection.findOptimalDeviceConnection(
          device: device,
          seagateDeviceID: seagateDeviceId,
          useCachedPaths: false,
        );
        if (ping.success && ping.baseUrl != null) {
          await dp.setHost(
            baseUrl: ping.baseUrl,
            deviceID: device.id,
            seagateDeviceID: seagateDeviceId,
            debugHostType: ping.debugHostType,
            login: email.value.trim(),
            devicePaths: dp.getCachedDevicePathsForDevice(seagateDeviceId)?.paths,
          );
          return (prepared: true, pathType: ping.pathType);
        }
      }

      if (device.about != null && device.baseUrl != null) {
        await dp.setHost(
          baseUrl: device.baseUrl,
          deviceID: device.id,
          seagateDeviceID: seagateDeviceId,
          debugHostType: device.debugHostType,
          login: email.value.trim(),
          devicePaths: seagateDeviceId == null
              ? null
              : dp.getCachedDevicePathsForDevice(seagateDeviceId)?.paths,
        );
        return (prepared: true, pathType: device.pathType);
      }

      dp.clearDevice(save: true);
      return (prepared: false, pathType: null);
    }

    bool isResetPasswordEnabled() =>
        !isLoading.value &&
        !isResetPasswordLoading.value &&
        email.value.isNotEmpty &&
        validateEmail(email.value) == null &&
        isDeviceSelectionValid(selectedDevice.value);

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

      // Returns `true` when the user taps Retry. We avoid invoking the retry
      // callback from inside the dialog button so the outer `finally` can
      // reset `isResetPasswordLoading` before the next call enters
      // `isResetPasswordEnabled()` (otherwise the recursive call would bail).
      Future<bool> showResetPasswordDialog({
        required String title,
        required String content,
        bool withRetryAction = false,
      }) async {
        if (!context.mounted) {
          return false;
        }
        final result = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: Text(title),
            content: Text(content),
            actions: !withRetryAction
                ? [TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text('OK'.tr()))]
                : [
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(false),
                      child: Text('cancel'.tr()),
                    ),
                    TextButton(
                      onPressed: () => Navigator.of(dialogContext).pop(true),
                      child: Text('retry'.tr()),
                    ),
                  ],
          ),
        );
        return result == true;
      }

      var shouldRetry = false;

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
              content: Text(
                'password_reset_email_sent_to'.tr(namedArgs: {'email': trimmedEmail}),
                style: const TextStyle(color: Colors.white, fontWeight: FontWeight.w500, fontSize: 14),
              ),
              backgroundColor: const Color(0xFF333333),
              behavior: SnackBarBehavior.floating,
              showCloseIcon: true,
              closeIconColor: Colors.white,
              duration: const Duration(seconds: 6),
              shape: const RoundedRectangleBorder(
                borderRadius: BorderRadius.all(Radius.circular(12)),
              ),
              margin: const EdgeInsets.all(16),
            ),
          );
        }
      } on ApiException catch (error) {
        log.warning('[ResetPassword] API failed: code=${error.code}, message=${error.message}');
        if (error.code == 401) {
          await showResetPasswordDialog(
            title: 'curator.email_not_registered_title'.tr(),
            content: 'curator.email_not_registered_description'.tr(),
          );
        } else if (error.code == 429) {
          await showResetPasswordDialog(
            title: 'curator.password_reset_too_many_requests_title'.tr(),
            content: 'curator.password_reset_too_many_requests_description'.tr(),
          );
        } else if (error.code >= 500) {
          shouldRetry = await showResetPasswordDialog(
            title: 'curator.email_unable_to_connect_title'.tr(),
            content: 'curator.email_unable_to_connect_description'.tr(),
            withRetryAction: true,
          );
        } else {
          warningMessage.value = 'errors.unable_to_reset_password'.tr();
        }
      } on TimeoutException catch (error, stackTrace) {
        log.warning('Reset password request timed out', error, stackTrace);
        shouldRetry = await showResetPasswordDialog(
          title: 'curator.email_unable_to_connect_title'.tr(),
          content: 'curator.email_unable_to_connect_description'.tr(),
          withRetryAction: true,
        );
      } catch (error, stackTrace) {
        log.warning('Failed to reset password', error, stackTrace);
        warningMessage.value = 'errors.unable_to_reset_password'.tr();
      } finally {
        isResetPasswordLoading.value = false;
      }

      if (shouldRetry && context.mounted) {
        log.info('[ResetPassword] Retry requested by user after error dialog');
        unawaited(handleResetPassword());
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

      final effectiveSelectedDevice = resolveSelectedDeviceForAction();
      if (!isDeviceSelectionValid(effectiveSelectedDevice)) {
        warningMessage.value = "login_form_no_device_selected".tr();
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

        final selected = resolveSelectedDeviceForAction();
        if (selected == null || !isDeviceSelectionValid(selected)) {
          warningMessage.value = "login_form_no_device_selected".tr();
          return;
        }

        final preparedBeforeLogin = await prepareDeviceHostForLogin(selected);
        if (!preparedBeforeLogin.prepared) {
          warningMessage.value = "login_form_server_error".tr();
          return;
        }

        final connectedBaseUrl = ref.read(deviceProvider).baseUrl;
        if (connectedBaseUrl == null) {
          warningMessage.value = "login_form_server_error".tr();
          log.warning('[Login] Aborted: connected device host is null after prepareDeviceHostForLogin');
          return;
        }
        final endpointSynced = await syncServerEndpointWithBaseUrl(
          baseUrl: connectedBaseUrl,
          flowTag: 'Login',
          pathType: null,
        );
        if (!endpointSynced) {
          return;
        }

        final isDeviceReady = await checkDeviceReadyForLogin();
        if (!isDeviceReady) {
          return;
        }

        invalidateAllApiRepositoryProviders(ref);

        final result = await ref.read(authProvider.notifier).login(email.value, passwordController.text);

        final dp = ref.read(deviceProvider.notifier);
        final seagateDeviceId = dp.seagateDeviceID ?? selected.remoteDevice?.seagateDeviceID;
        final paths = dp.resolveDevicePathsForDisplay(deviceRemoteId: seagateDeviceId);
        if (paths.isNotEmpty) {
          await ref.read(devicePathRefreshServiceProvider).processAndSavePaths(paths);
        }

        if (result.shouldChangePassword && !result.isAdmin) {
          context.pushRoute(const ChangePasswordRoute());
        } else {
          final onboardingWasShown = Store.tryGet(StoreKey.onboardingWasShown) ?? false;
          if (!onboardingWasShown) {
            if (Store.isBetaTimelineEnabled) {
              // Start remote sync during onboarding so the timeline is ready after permissions.
              unawaited(ref.read(backgroundSyncProvider).syncRemote());
              ref.read(websocketProvider.notifier).connect();
            }
            context.replaceRoute(const CuratorOnboardingRoute());
            return;
          }

          final isBeta = Store.isBetaTimelineEnabled;
          if (isBeta) {
            await ref.read(galleryPermissionNotifier.notifier).requestGalleryPermission();
            unawaited(handleSyncFlow());
            ref.read(websocketProvider.notifier).connect();
            context.replaceRoute(const TabShellRoute());
            return;
          }

          if (ref.read(galleryPermissionNotifier.notifier).hasPermission) {
            unawaited(ref.read(backupProvider.notifier).resumeBackup());
          }
          ref.read(websocketProvider.notifier).connect();
          context.replaceRoute(const TabControllerRoute());
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
                child: const LoginBrandHeader(),
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
                            isCantFindDeviceLoading.value
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
