import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:homecloud_frontend/api/remote_access.swagger.dart';
import 'package:homecloud_frontend/providers/hcdevice.provider.dart';
import 'package:homecloud_frontend/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/widgets/forms/pin_input.dart';

class RemoteCodeModal extends HookConsumerWidget {
  final Future<void> Function() onSuccess;
  final void Function(ApiErrorMessage, Object) handleError;
  final Future<void> Function() initiateRemoteAccess;

  const RemoteCodeModal({
    super.key,
    required this.onSuccess,
    required this.handleError,
    required this.initiateRemoteAccess,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remoteCodeController = useTextEditingController.fromValue(TextEditingValue.empty);
    final remoteCodeLoading = useState<bool>(false);
    final remoteCodeExpired = useState<bool>(false);
    final remoteCodeErrorText = useState<String?>(null);
    final isValidating = useState<bool>(false);
    final codeLength = useState<int>(0);

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
          onSuccess();
          if (context.mounted) {
            Navigator.of(context).pop(); // Close the modal
          }
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
      } finally {
        remoteCodeLoading.value = false;
        isValidating.value = false;
      }
    }

    final actions = [
      () {
        final isLoading = remoteCodeLoading.value;
        return TextButton(
          onPressed: isLoading ? null : () {
            Navigator.of(context).pop();
            onSuccess();
          },
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.all(12.0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'curator.sign_in_screen_remote_code_skip'.tr(),
              ),
            ],
          ),
        );
      },
      // Allow access button - visible when expired
      if (remoteCodeExpired.value)
        () {
          final isLoading = remoteCodeLoading.value;
          return TextButton(
            onPressed: isLoading ? null : () {
              // Clear error state and code input when resending
              remoteCodeErrorText.value = null;
              remoteCodeController.clear();
              remoteCodeExpired.value = false;
              initiateRemoteAccess();
            },
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.all(12.0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        context.colorScheme.primary,
                      ),
                    ),
                  )
                : Text(
                    'curator.sign_in_screen_remote_code_resend'.tr(),
                    style: TextStyle(
                      color: context.colorScheme.primary,
                    ),
                  ),
          );
        },
      // Submit code button - visible when not expired
      if (!remoteCodeExpired.value)
        () {
          final isLoading = remoteCodeLoading.value;
          final isDisabled = codeLength.value != 6 || isValidating.value;
          return TextButton(
            onPressed: (isLoading || isDisabled) ? null : checkRemoteAccessCode,
            style: TextButton.styleFrom(
              minimumSize: Size.zero,
              padding: const EdgeInsets.all(12.0),
              tapTargetSize: MaterialTapTargetSize.shrinkWrap,
            ),
            child: isLoading
                ? SizedBox(
                    width: 16,
                    height: 16,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(
                        context.colorScheme.primary,
                      ),
                    ),
                  )
                : Text(
                    'curator.sign_in_screen_remote_code_allow_access'.tr(),
                    style: TextStyle(
                      color: isDisabled
                          ? context.colorScheme.secondary
                          : context.colorScheme.primary,
                    ),
                  ),
          );
        },
    ];

    return AlertDialog(
      title: Text('curator.sign_in_screen_remote_code_title'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('curator.sign_in_screen_remote_code_description'.tr(), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 24),
          Opacity(
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
              ),
            ),
          ),
          // Error message display
          if (remoteCodeErrorText.value != null)
            ...[
              const SizedBox(height: 8),
              Text(
                remoteCodeErrorText.value!,
                style: context.textTheme.bodySmall?.copyWith(
                  color: context.colorScheme.error,
                ),
                maxLines: 2,
              ),]
        ],
      ),
      actions: actions.map((actionBuilder) => actionBuilder()).toList(),
    );
  }
}

/// Show modal dialog for remote code input
Future<void> showRemoteCodeModal(
  BuildContext context,
  Future<void> Function() onSuccess,
  void Function(ApiErrorMessage, Object) handleError,
  Future<void> Function() initiateRemoteAccess,
) {
  return showDialog(
    context: context,
    barrierDismissible: true,
    builder: (BuildContext context) =>
        RemoteCodeModal(onSuccess: onSuccess, handleError: handleError, initiateRemoteAccess: initiateRemoteAccess),
  );
}
