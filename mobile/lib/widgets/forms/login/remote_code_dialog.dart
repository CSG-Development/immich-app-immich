import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hc_device/data/errors/domain_errors.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/services/client_device_name.helper.dart';
import 'package:immich_mobile/widgets/forms/pin_input.dart';
import 'package:pinput/pinput.dart';

const int defaultResendCooldownSeconds = 60;

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
      remoteCodeInitiateError.value = true;
      if (result.error == RemoteCodeModalError.notAllowed) {
        remoteCodeErrorText.value = 'curator.email_not_registered_error'.tr();
        emailNotAllowed.value = true;
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
          } catch (_) {
            // Keep the modal usable when post-OTP flows (discovery/reconnect)
            // fail after successful token validation.
            remoteCodeErrorText.value = 'curator.remote_access_server_unreachable'.tr();
          }
        } else {
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

    final isWide = context.isTablet || context.orientation == Orientation.landscape;

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
    return AlertDialog(
      title: Text('curator.sign_in_screen_remote_code_title'.tr()),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 400 : double.infinity),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('curator.sign_in_screen_remote_code_description'.tr(), style: Theme.of(context).textTheme.bodyMedium),
            const SizedBox(height: 24),
            Opacity(
              opacity: (remoteCodeLoading.value || isValidating.value) ? 0.5 : 1.0,
              child: AbsorbPointer(
                absorbing: remoteCodeLoading.value || isValidating.value,
                child: Builder(
                  builder: (context) {
                    // Compute pin size for custom themes
                    const minimumPadding = 18.0;
                    const gapWidth = 3.0;
                    final screenWidth = MediaQuery.sizeOf(context).width;
                    double pinWidth = (screenWidth - (minimumPadding * 2) - (gapWidth * 5)) / 6;
                    if (pinWidth > 60) pinWidth = 60;
                    final pinHeight = pinWidth / (60 / 64);

                    // Custom default theme: grey border, no background
                    final customDefaultPinTheme = PinTheme(
                      width: pinWidth,
                      height: pinHeight,
                      textStyle: TextStyle(fontSize: 24, color: context.colorScheme.onSurface),
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.all(Radius.circular(19)),
                        border: Border.all(
                          color: context.isDarkTheme ? const Color(0xFF616161) : const Color(0xFFCBCDD3),
                        ),
                        color: Colors.transparent,
                      ),
                    );

                    // Custom focused theme: primary border, no background
                    final customFocusedPinTheme = customDefaultPinTheme.copyWith(
                      decoration: BoxDecoration(
                        borderRadius: const BorderRadius.all(Radius.circular(19)),
                        border: Border.all(
                          color: context.isDarkTheme ? const Color(0xFF64B5F6) : const Color(0xFF1976D2),
                          width: 2,
                        ),
                        color: Colors.transparent,
                      ),
                    );

                    // Custom error theme: specific error colors, no background
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

                    return PinInput(
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
                    );
                  },
                ),
              ),
            ),
            // Error message display
            if (remoteCodeErrorText.value != null) ...[
              const SizedBox(height: 4),
              Padding(
                padding: const EdgeInsets.only(left: 16),
                child: Text(
                  remoteCodeErrorText.value!,
                  textAlign: TextAlign.left,
                  style: context.textTheme.bodySmall?.copyWith(
                    color: context.isDarkTheme ? const Color(0xFFF28F8C) : const Color(0xFFF44336),
                  ),
                  maxLines: 2,
                ),
              ),
            ],
          ],
        ),
      ),
      actions: actions.map((actionBuilder) => actionBuilder()).toList(),
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
  int extractRetryAfterSeconds(dynamic response) {
    final message = (response.error ?? '').toString();
    final match = RegExp(r'after\s+(\d+)\s+seconds', caseSensitive: false)
        .firstMatch(message);
    return int.tryParse(match?.group(1) ?? '') ?? defaultResendCooldownSeconds;
  }

  Future<RemoteCodeInitiateResult> sendCode() async {
    try {
      final clientFriendlyName = await ClientDeviceNameHelper.getClientFriendlyName();
      await remoteProvider.getPinnedApi();
      final response = await remoteProvider.initiateEmailAccess(
        email: email,
        clientFriendlyName: clientFriendlyName,
      );
      if (response.isSuccessful) {
        await remoteProvider.setReference(response.body?.reference);
        return const RemoteCodeInitiateResult(
          success: true,
          retryAfterSeconds: defaultResendCooldownSeconds,
        );
      }
      if (response.statusCode == 401 || response.statusCode == 403) {
        return const RemoteCodeInitiateResult(
          success: false,
          error: RemoteCodeModalError.notAllowed,
        );
      }
      if (response.statusCode == 429) {
        return RemoteCodeInitiateResult(
          success: true,
          retryAfterSeconds: extractRetryAfterSeconds(response),
        );
      }
      return const RemoteCodeInitiateResult(
        success: false,
        error: RemoteCodeModalError.server,
      );
    } catch (_) {
      return const RemoteCodeInitiateResult(
        success: false,
        error: RemoteCodeModalError.server,
      );
    }
  }

  Future<RemoteCodeValidationResult> validateCode(String code) async {
    try {
      await remoteProvider.getPinnedApi();
      final reference = remoteProvider.reference;
      if (reference == null || reference.isEmpty) {
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
        return const RemoteCodeValidationResult(success: true);
      }
      final classified = remoteProvider.classifyCodeFailure(response);
      return RemoteCodeValidationResult(
        success: false,
        type: classified.type,
        message: classified.message,
      );
    } catch (_) {
      return const RemoteCodeValidationResult(
        success: false,
        type: RemoteCodeFailureType.unknown,
      );
    }
  }

  RemoteCodeInitiateResult? initialInitiateResult;
  if (!skipInitialCodeSend) {
    initialInitiateResult = await sendCode();
  }

  onDialogPresented?.call();
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
  );
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
