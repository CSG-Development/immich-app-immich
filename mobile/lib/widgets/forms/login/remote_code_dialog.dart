import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hc_device/remote_auth.provider.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/services/client_device_name.helper.dart';
import 'package:immich_mobile/widgets/forms/pin_input.dart';
import 'package:pinput/pinput.dart';

class RemoteCodeModal extends HookConsumerWidget {
  final Future<void> Function()? onSuccess;
  final String email;
  final VoidCallback? onEmailNotAllowed;

  const RemoteCodeModal({super.key, required this.email, this.onSuccess, this.onEmailNotAllowed});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remoteCodeController = useTextEditingController.fromValue(TextEditingValue.empty);
    final remoteCodeLoading = useState<bool>(false);
    final remoteCodeExpired = useState<bool>(false);
    final remoteCodeInitiateError = useState<bool>(false);
    final remoteCodeErrorText = useState<String?>(null);
    final emailNotAllowed = useState<bool?>(false);
    final tooManyRequests = useState<bool?>(false);
    final unableToConnect = useState<bool?>(false);
    final isValidating = useState<bool>(false);
    final codeLength = useState<int>(0);

    final remoteAuth = ref.watch(remoteAuthProvider);

    Future<void> sendRemoteCode() async {
      // Avoid overlapping send operations
      if (remoteCodeLoading.value && !remoteCodeExpired.value) {
        return;
      }
      remoteCodeInitiateError.value = false;
      remoteCodeLoading.value = true;
      remoteCodeErrorText.value = null;
      emailNotAllowed.value = false;
      tooManyRequests.value = false;
      unableToConnect.value = false;

      try {
        final clientFriendlyName = await ClientDeviceNameHelper.getClientFriendlyName();
        await remoteAuth.initiate(email: email, clientFriendlyName: clientFriendlyName);

        final state = remoteAuth.state;
        if (state.error != null) {
          remoteCodeInitiateError.value = true;
          switch (state.error) {
            case RemoteAuthError.server:
              remoteCodeErrorText.value = 'curator.remote_access_connection_error'.tr();
              unableToConnect.value = true;
            case RemoteAuthError.notAllowed:
              remoteCodeErrorText.value = 'curator.email_not_registered_error'.tr();
              emailNotAllowed.value = true;
            case RemoteAuthError.tooManyRequests:
              remoteCodeErrorText.value = 'curator.email_not_registered_error'.tr();
              tooManyRequests.value = true;
            default:
              remoteCodeErrorText.value = state.errorMessage ?? 'curator.remote_access_connection_error'.tr();
              break;
          }
        } else {
          onSuccess?.call();
        }
      } catch (_) {
        remoteCodeInitiateError.value = true;
        remoteCodeErrorText.value = 'curator.remote_access_connection_error'.tr();
      } finally {
        remoteCodeLoading.value = false;
      }
    }

    useEffect(() {
      void listener() {
        codeLength.value = remoteCodeController.text.length;
      }

      remoteCodeController.addListener(listener);
      return () => remoteCodeController.removeListener(listener);
    }, [remoteCodeController]);

    // Initiate remote access (send code) when the dialog opens
    useEffect(() {
      sendRemoteCode();
      return null;
    }, []);

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

      final success = await remoteAuth.validateCode(code);
      final state = remoteAuth.state;

      if (success) {
        onSuccess?.call();
        if (context.mounted) Navigator.of(context).pop();
      } else {
        switch (state.error) {
          case RemoteAuthError.invalidCode:
            remoteCodeErrorText.value = 'curator.sign_in_screen_field_remote_code_error_invalid'.tr();
            break;
          case RemoteAuthError.expiredCode:
            remoteCodeExpired.value = true;
            remoteCodeErrorText.value = 'curator.sign_in_screen_field_remote_code_error_expired'.tr();
            break;
          case RemoteAuthError.network:
            remoteCodeErrorText.value = 'curator.remote_access_server_unreachable'.tr();
            break;
          default:
            remoteCodeErrorText.value = state.errorMessage ?? 'curator.remote_access_server_unreachable'.tr();
            break;
        }
      }

      remoteCodeLoading.value = false;
      isValidating.value = false;
    }

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
            onPressed: isLoading
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
                    'curator.sign_in_screen_remote_code_resend'.tr(),
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
    if (tooManyRequests.value == true) {
      return AlertDialog(
        title: Text('curator.email_too_many_requests_title'.tr()),
        content: Text('curator.email_too_many_requests_description'.tr()),
        actions: [TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('OK'.tr()))],
      );
    }
    if (unableToConnect.value == true) {
      return AlertDialog(
        title: Text('curator.email_unable_to_connect_title'.tr()),
        content: Text('curator.email_unable_to_connect_description'.tr()),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(), child: Text('cancel'.tr())),
          TextButton(onPressed: () => sendRemoteCode(), child: Text('retry'.tr())),
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
  required String email,
  Future<void> Function()? onSuccess,
  VoidCallback? onEmailNotAllowed,
}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) =>
        RemoteCodeModal(onSuccess: onSuccess, onEmailNotAllowed: onEmailNotAllowed, email: email),
  );
}
