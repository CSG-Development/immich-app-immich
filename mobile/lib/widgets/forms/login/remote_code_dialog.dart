import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hc_device/data/errors/domain_errors.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/pages/security/widgets/lock_utils.dart';
import 'package:immich_mobile/services/client_device_name.helper.dart';
import 'package:immich_mobile/widgets/forms/pin_input.dart';
import 'package:logging/logging.dart';
import 'package:pinput/pinput.dart';

final _otpLog = Logger('RemoteCodeDialog');

const int defaultResendCooldownSeconds = 60;

Future<void>? _activeRemoteCodeModalFuture;

/// True while a remote code modal is being presented (including initial code send).
bool get isRemoteCodeModalShowing => _activeRemoteCodeModalFuture != null;

class RemoteCodeModal extends HookWidget {
  final Future<void> Function()? onSuccess;
  final String email;
  final VoidCallback? onEmailNotAllowed;
  final Future<RemoteCodeInitiateResult> Function() sendCode;
  final Future<RemoteCodeValidationResult> Function(String code) validateCode;
  final RemoteCodeInitiateResult? initialInitiateResult;

  const RemoteCodeModal({
    super.key,
    required this.email,
    required this.sendCode,
    required this.validateCode,
    this.initialInitiateResult,
    this.onSuccess,
    this.onEmailNotAllowed,
  });

  @override
  Widget build(BuildContext context) {
    final remoteCodeController = useTextEditingController.fromValue(TextEditingValue.empty);
    final remoteCodeLoading = useState<bool>(false);
    final remoteCodeExpired = useState<bool>(false);
    final remoteCodeInitiateError = useState<bool>(false);
    final remoteCodeErrorText = useState<String?>(null);
    final emailNotAllowed = useState<bool?>(false);
    final isValidating = useState<bool>(false);
    final codeLength = useState<int>(0);
    final resendCooldownSeconds = useState<int>(0);

    void applyInitiateResult(RemoteCodeInitiateResult result) {
      if (result.success) {
        resendCooldownSeconds.value =
            result.retryAfterSeconds ?? defaultResendCooldownSeconds;
        remoteCodeExpired.value = false;
        remoteCodeInitiateError.value = false;
        remoteCodeErrorText.value = null;
        emailNotAllowed.value = false;
        return;
      }

      if (result.retryAfterSeconds != null) {
        resendCooldownSeconds.value = result.retryAfterSeconds!;
      }

      remoteCodeInitiateError.value = true;
      if (result.error == RemoteCodeModalError.notAllowed) {
        remoteCodeErrorText.value = 'curator.email_not_registered_error'.tr();
        emailNotAllowed.value = true;
      } else if (result.error == RemoteCodeModalError.tooManyRequests) {
        remoteCodeErrorText.value = 'curator.email_too_many_requests_description'.tr();
        emailNotAllowed.value = false;
      } else {
        remoteCodeErrorText.value = 'curator.remote_access_server_unreachable'.tr();
      }
    }

    Future<void> sendRemoteCode() async {
      // Avoid overlapping send operations
      if (remoteCodeLoading.value && !remoteCodeExpired.value) {
        return;
      }
      remoteCodeInitiateError.value = false;
      remoteCodeLoading.value = true;
      remoteCodeErrorText.value = null;
      emailNotAllowed.value = false;
      remoteCodeExpired.value = false;

      final result = await sendCode();
      applyInitiateResult(result);
      remoteCodeLoading.value = false;
    }

    useEffect(() {
      final initial = initialInitiateResult;
      if (initial != null) {
        applyInitiateResult(initial);
      }
      return null;
    }, []);

    useEffect(() {
      if (resendCooldownSeconds.value <= 0) {
        return null;
      }
      final timer = Stream.periodic(const Duration(seconds: 1)).listen((_) {
        if (resendCooldownSeconds.value > 0) {
          resendCooldownSeconds.value -= 1;
        }
      });
      return timer.cancel;
    }, [resendCooldownSeconds.value]);

    useEffect(() {
      void listener() {
        codeLength.value = remoteCodeController.text.length;
      }

      remoteCodeController.addListener(listener);
      return () => remoteCodeController.removeListener(listener);
    }, [remoteCodeController]);

    /// Validate the remote access code and get access and refresh tokens
    ///
    /// Then get the remote devices
    Future<void> checkRemoteAccessCode() async {
      // Prevent duplicate validation calls
      if (isValidating.value || remoteCodeLoading.value) {
        return;
      }

      final code = remoteCodeController.text;
      if (codeLength.value != 6) {
        return;
      }

      isValidating.value = true;
      remoteCodeLoading.value = true;
      remoteCodeErrorText.value = null;

      try {
        final result = await validateCode(code);
        if (result.success) {
          try {
            if (onSuccess != null) {
              await onSuccess!();
            }
            if (context.mounted) Navigator.of(context).pop();
          } catch (error, stackTrace) {
            // Keep the modal usable when post-OTP flows (discovery/reconnect)
            // fail after successful token validation.
            _otpLog.warning('[OTP] post-success callback failed', error, stackTrace);
            remoteCodeErrorText.value = 'curator.remote_access_server_unreachable'.tr();
          }
        } else {
          _otpLog.info('[OTP] code validation failed type=${result.type.name} message=${result.message}');
          switch (result.type) {
            case RemoteCodeFailureType.invalidCode:
              remoteCodeErrorText.value = 'curator.sign_in_screen_field_remote_code_error_invalid'.tr();
              break;
            case RemoteCodeFailureType.expiredCode:
              remoteCodeExpired.value = true;
              remoteCodeErrorText.value = 'curator.sign_in_screen_field_remote_code_error_expired'.tr();
              break;
            case RemoteCodeFailureType.unauthorized:
              remoteCodeErrorText.value = 'curator.email_not_registered_error'.tr();
              break;
            case RemoteCodeFailureType.unknown:
              remoteCodeErrorText.value = result.message ?? 'curator.remote_access_server_unreachable'.tr();
              break;
          }
        }
      } finally {
        remoteCodeLoading.value = false;
        isValidating.value = false;
      }
    }

    final resendLabel = resendCooldownSeconds.value > 0
        ? '${'curator.sign_in_screen_remote_code_resend'.tr()} (${resendCooldownSeconds.value}s)'
        : 'curator.sign_in_screen_remote_code_resend'.tr();

    final actions = [
      () {
        final isLoading = remoteCodeLoading.value;
        return TextButton(
          onPressed: isLoading ? null : () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.all(12.0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Row(mainAxisSize: MainAxisSize.min, children: [Text('curator.sign_in_screen_remote_code_skip'.tr())]),
        );
      },
      // Allow access button - visible when expired
      if (remoteCodeExpired.value || remoteCodeInitiateError.value)
        () {
          final isLoading = remoteCodeLoading.value;
          return TextButton(
            onPressed: isLoading || resendCooldownSeconds.value > 0
                ? null
                : () {
                    // Clear error state and code input when resending
                    remoteCodeErrorText.value = null;
                    remoteCodeController.clear();
                    remoteCodeExpired.value = false;
                    sendRemoteCode();
                  },
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.all(12.0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: isLoading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                : Text(
                    resendLabel,
                    style: TextStyle(color: context.colorScheme.primary),
                  ),
          );
        },
      // Submit code button - visible when not expired
      if (!remoteCodeExpired.value && !remoteCodeInitiateError.value)
        () {
          final isLoading = remoteCodeLoading.value;
          final isDisabled = codeLength.value != 6 || isValidating.value || remoteCodeErrorText.value != null;
          return TextButton(
            onPressed: (isLoading || isDisabled) ? null : checkRemoteAccessCode,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.all(12.0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: isLoading
                ? const SizedBox(width: 24, height: 24, child: CircularProgressIndicator())
                : Text(
                    'curator.sign_in_screen_remote_code_allow_access'.tr(),
                    style: TextStyle(color: isDisabled ? const Color(0xFF9E9E9E) : context.colorScheme.primary),
                  ),
          );
        },
    ];

    final mediaQuery = MediaQuery.of(context);
    final useLandscapePhoneLayout = isLandscapePhone(context);
    final isWide = context.isTablet || mediaQuery.orientation == Orientation.landscape;

    final landscapeDialogWidth = useLandscapePhoneLayout
        ? (mediaQuery.size.width - mediaQuery.padding.horizontal - 48).clamp(280.0, 400.0)
        : null;

    // Dialog horizontal inset (24) + inner padding (24) on each side.
    const dialogHorizontalInsets = 24.0 * 4;
    final pinContentWidth = landscapeDialogWidth != null
        ? landscapeDialogWidth - 40
        : isWide
        ? 400.0
        : (mediaQuery.size.width - dialogHorizontalInsets);
    const gapWidth = 3.0;
    var pinWidth = (pinContentWidth - (gapWidth * 5)) / 6;
    final maxPinWidth = useLandscapePhoneLayout ? 44.0 : 60.0;
    if (pinWidth > maxPinWidth) {
      pinWidth = maxPinWidth;
    }
    final pinHeight = pinWidth / (60 / 64);

    final customDefaultPinTheme = PinTheme(
      width: pinWidth,
      height: pinHeight,
      textStyle: TextStyle(fontSize: 24, color: context.colorScheme.onSurface),
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(19)),
        border: Border.all(
          color: context.colorScheme.outlineVariant,
        ),
        color: Colors.transparent,
      ),
    );

    final customFocusedPinTheme = customDefaultPinTheme.copyWith(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(19)),
        border: Border.all(
          color: context.colorScheme.primary,
          width: 2,
        ),
        color: Colors.transparent,
      ),
    );

    final customErrorPinTheme = customDefaultPinTheme.copyWith(
      decoration: BoxDecoration(
        borderRadius: const BorderRadius.all(Radius.circular(19)),
        border: Border.all(
          color: context.isDarkTheme ? const Color(0xFFF28F8C) : const Color(0xFFF44336),
          width: 2,
        ),
        color: Colors.transparent,
      ),
    );

    final builtActions = actions.map((actionBuilder) => actionBuilder()).toList();

    Widget buildPinField() {
      return Opacity(
        opacity: (remoteCodeLoading.value || isValidating.value) ? 0.5 : 1.0,
        child: AbsorbPointer(
          absorbing: remoteCodeLoading.value || isValidating.value,
          child: PinInput(
            controller: remoteCodeController,
            onChanged: (value) {
              if (remoteCodeErrorText.value != null) {
                remoteCodeErrorText.value = null;
              }
            },
            length: 6,
            autoFocus: true,
            hasError: remoteCodeErrorText.value != null,
            defaultPinTheme: customDefaultPinTheme,
            focusedPinTheme: customFocusedPinTheme,
            errorPinTheme: customErrorPinTheme,
            cursor: Align(
              alignment: Alignment.center,
              child: Container(width: 2, height: 22, color: context.primaryColor),
            ),
          ),
        ),
      );
    }

    Widget? buildErrorText() {
      if (remoteCodeErrorText.value == null) {
        return null;
      }
      return Padding(
        padding: const EdgeInsets.only(left: 16, top: 4),
        child: Text(
          remoteCodeErrorText.value!,
          textAlign: TextAlign.left,
          style: context.textTheme.bodySmall?.copyWith(
            color: context.isDarkTheme ? const Color(0xFFF28F8C) : const Color(0xFFF44336),
          ),
          maxLines: 3,
        ),
      );
    }

    if (emailNotAllowed.value == true) {
      return AlertDialog(
        title: Text('curator.email_not_registered_title'.tr()),
        content: Text('curator.email_not_registered_description'.tr()),
        actions: [
          TextButton(
            onPressed: () {
              Navigator.of(context).pop();
              onEmailNotAllowed?.call();
            },
            child: Text('OK'.tr()),
          ),
        ],
      );
    }
    if (useLandscapePhoneLayout) {
      // Pin to the top with fixed insets. Do not fold viewInsets into padding/constraints:
      // that re-centers or shrinks the route and pushes the dialog off-screen.
      final keyboardHeight = mediaQuery.viewInsets.bottom;
      const verticalChrome = 52.0; // top inset + dialog vertical padding
      final maxScrollHeight = (mediaQuery.size.height -
              mediaQuery.padding.top -
              keyboardHeight -
              verticalChrome)
          .clamp(120.0, mediaQuery.size.height);
      final dialogWidth = landscapeDialogWidth!;

      final landscapeDialog = Dialog(
        alignment: Alignment.topCenter,
        insetPadding: EdgeInsets.fromLTRB(
          24 + mediaQuery.padding.left,
          mediaQuery.padding.top + 8,
          24 + mediaQuery.padding.right,
          16,
        ),
        child: SizedBox(
          width: dialogWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxScrollHeight),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'curator.sign_in_screen_remote_code_title'.tr(),
                      style: context.textTheme.titleSmall,
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'curator.sign_in_screen_remote_code_description'.tr(),
                      style: Theme.of(context).textTheme.bodyMedium,
                    ),
                    const SizedBox(height: 16),
                    buildPinField(),
                    if (buildErrorText() case final errorText?) errorText,
                    const SizedBox(height: 4),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(children: builtActions),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      return MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: landscapeDialog,
      );
    }

    return AlertDialog(
      title: Text('curator.sign_in_screen_remote_code_title'.tr()),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 400 : double.infinity),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'curator.sign_in_screen_remote_code_description'.tr(),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
            const SizedBox(height: 24),
            buildPinField(),
            if (buildErrorText() case final errorText?) errorText,
          ],
        ),
      ),
      actions: builtActions,
    );
  }
}

/// Show modal dialog for remote code input
Future<void> showRemoteCodeModal({
  required BuildContext context,
  required RemoteProvider remoteProvider,
  required String email,
  Future<void> Function()? onSuccess,
  VoidCallback? onEmailNotAllowed,
  VoidCallback? onDialogPresented,
  /// When true, skips the automatic [sendCode] before the dialog (e.g. Remote Access
  /// session already present and an extra initiate request is unnecessary).
  bool skipInitialCodeSend = false,
}) async {
  final activeSession = _activeRemoteCodeModalFuture;
  if (activeSession != null) {
    _otpLog.info('[OTP] showRemoteCodeModal join existing session email=$email');
    return activeSession;
  }

  final session = _presentRemoteCodeModal(
    context: context,
    remoteProvider: remoteProvider,
    email: email,
    onSuccess: onSuccess,
    onEmailNotAllowed: onEmailNotAllowed,
    onDialogPresented: onDialogPresented,
    skipInitialCodeSend: skipInitialCodeSend,
  );
  _activeRemoteCodeModalFuture = session;
  try {
    await session;
  } finally {
    if (identical(_activeRemoteCodeModalFuture, session)) {
      _activeRemoteCodeModalFuture = null;
    }
  }
}

Future<void> _presentRemoteCodeModal({
  required BuildContext context,
  required RemoteProvider remoteProvider,
  required String email,
  Future<void> Function()? onSuccess,
  VoidCallback? onEmailNotAllowed,
  VoidCallback? onDialogPresented,
  required bool skipInitialCodeSend,
}) async {
  _otpLog.info(
    '[OTP] showRemoteCodeModal start email=$email skipInitialCodeSend=$skipInitialCodeSend',
  );
  int extractRetryAfterSeconds(dynamic response) {
    final message = (response.error ?? '').toString();
    final match = RegExp(r'after\s+(\d+)\s+seconds', caseSensitive: false)
        .firstMatch(message);
    return int.tryParse(match?.group(1) ?? '') ?? defaultResendCooldownSeconds;
  }

  Future<RemoteCodeInitiateResult> sendCode() async {
    _otpLog.info('[OTP] sendCode start email=$email');
    try {
      final clientFriendlyName = await ClientDeviceNameHelper.getClientFriendlyName();
      await remoteProvider.getPinnedApi();
      final response = await remoteProvider.initiateEmailAccess(
        email: email,
        clientFriendlyName: clientFriendlyName,
      );
      if (response.isSuccessful) {
        await remoteProvider.setReference(response.body?.reference);
        _otpLog.info('[OTP] sendCode success email=$email');
        return const RemoteCodeInitiateResult(
          success: true,
          retryAfterSeconds: defaultResendCooldownSeconds,
        );
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        _otpLog.warning('[OTP] sendCode not allowed status=${response.statusCode} email=$email');
        return const RemoteCodeInitiateResult(
          success: false,
          error: RemoteCodeModalError.notAllowed,
        );
      }
      if (response.statusCode == 429) {
        final retryAfter = extractRetryAfterSeconds(response);
        _otpLog.info('[OTP] sendCode rate-limited retryAfter=${retryAfter}s email=$email');
        return RemoteCodeInitiateResult(
          success: false,
          error: RemoteCodeModalError.tooManyRequests,
          retryAfterSeconds: retryAfter,
        );
      }
      _otpLog.warning('[OTP] sendCode server error status=${response.statusCode} email=$email');
      return const RemoteCodeInitiateResult(
        success: false,
        error: RemoteCodeModalError.server,
      );
    } catch (error, stackTrace) {
      _otpLog.warning('[OTP] sendCode exception email=$email', error, stackTrace);
      return const RemoteCodeInitiateResult(
        success: false,
        error: RemoteCodeModalError.server,
      );
    }
  }

  Future<RemoteCodeValidationResult> validateCode(String code) async {
    _otpLog.info('[OTP] validateCode start email=$email');
    try {
      await remoteProvider.getPinnedApi();
      final reference = remoteProvider.reference;
      if (reference == null || reference.isEmpty) {
        _otpLog.warning('[OTP] validateCode abort reason=missing_reference email=$email');
        return const RemoteCodeValidationResult(
          success: false,
          type: RemoteCodeFailureType.unknown,
        );
      }
      final response = await remoteProvider.validateEmailCode(
        code: code,
        reference: reference,
      );
      if (response.isSuccessful) {
        await remoteProvider.setAuthToken(auth: response.body!);
        _otpLog.info('[OTP] validateCode success email=$email');
        return const RemoteCodeValidationResult(success: true);
      }
      final classified = remoteProvider.classifyCodeFailure(response);
      _otpLog.warning(
        '[OTP] validateCode failed email=$email status=${response.statusCode} type=${classified.type.name}',
      );
      return RemoteCodeValidationResult(
        success: false,
        type: classified.type,
        message: classified.message,
      );
    } catch (error, stackTrace) {
      _otpLog.warning('[OTP] validateCode exception email=$email', error, stackTrace);
      return const RemoteCodeValidationResult(
        success: false,
        type: RemoteCodeFailureType.unknown,
      );
    }
  }

  RemoteCodeInitiateResult? initialInitiateResult;
  if (!skipInitialCodeSend) {
    initialInitiateResult = await sendCode();
    _otpLog.info(
      '[OTP] initial sendCode result success=${initialInitiateResult.success} '
      'error=${initialInitiateResult.error?.name ?? '-'}',
    );
  } else {
    _otpLog.info('[OTP] skipping initial sendCode email=$email');
  }

  onDialogPresented?.call();
  _otpLog.info('[OTP] presenting modal email=$email');
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) =>
        RemoteCodeModal(
        onSuccess: onSuccess,
        sendCode: sendCode,
        validateCode: validateCode,
        initialInitiateResult: initialInitiateResult,
        onEmailNotAllowed: onEmailNotAllowed,
        email: email,
        ),
  ).whenComplete(() {
    _otpLog.info('[OTP] modal dismissed email=$email remoteAuth=${remoteProvider.isAuthenticated}');
  });
}

enum RemoteCodeModalError { notAllowed, tooManyRequests, server }

class RemoteCodeValidationResult {
  final bool success;
  final RemoteCodeFailureType type;
  final String? message;
  const RemoteCodeValidationResult({
    required this.success,
    this.type = RemoteCodeFailureType.unknown,
    this.message,
  });
}

class RemoteCodeInitiateResult {
  final bool success;
  final int? retryAfterSeconds;
  final RemoteCodeModalError? error;
  const RemoteCodeInitiateResult({
    required this.success,
    this.retryAfterSeconds,
    this.error,
  });
}
