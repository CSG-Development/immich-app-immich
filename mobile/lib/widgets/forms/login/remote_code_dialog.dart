import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:homecloud_frontend/api/remote_access.swagger.dart';
import 'package:homecloud_frontend/providers/hcdevice.provider.dart';
import 'package:homecloud_frontend/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class RemoteCodeModal extends HookConsumerWidget {
  final Future<void> Function() getRemoteDevices;
  final void Function(ApiErrorMessage, Object) handleError;
  final Future<void> Function() initiateRemoteAccess;

  const RemoteCodeModal({
    super.key,
    required this.getRemoteDevices,
    required this.handleError,
    required this.initiateRemoteAccess,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final remoteCodeController = useTextEditingController.fromValue(TextEditingValue.empty);
    final remoteCodeFocusNode = useFocusNode();
    final loggingIn = useState<bool>(false);

    final remoteCodeLoading = useState<bool>(false);
    final remoteCodeExpired = useState<bool>(false);

    String lastCodeChecked = '';

    final remoteCodeErrorText = useState<String?>(null);

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
        }
      }
      remoteCodeLoading.value = false;
    }

    return AlertDialog(
      title: Text('curator.sign_in_screen_remote_code_title'.tr()),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text('curator.sign_in_screen_remote_code_description'.tr(), style: Theme.of(context).textTheme.bodyMedium),
          const SizedBox(height: 16),
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
                  ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
                  : null,
            ),
            autofillHints: [AutofillHints.oneTimeCode],
            controller: remoteCodeController,
            keyboardType: TextInputType.number,
            textInputAction: TextInputAction.done,
            focusNode: remoteCodeFocusNode,
            enabled: !remoteCodeLoading.value && !loggingIn.value,
            autovalidateMode: AutovalidateMode.onUserInteraction,
            onChanged: (value) {
              if (remoteCodeErrorText.value != null) {
                remoteCodeErrorText.value = null;
              }
            },
          ),
        ],
      ),
      actions: [
        if (remoteCodeExpired.value)
          TextButton(
            onPressed: () {
              if (context.mounted) Navigator.of(context).pop();
            },
            child: Text('curator.sign_in_screen_remote_code_cancel'.tr()),
          ),
        ElevatedButton(
          onPressed: () {
            if (context.mounted) Navigator.of(context).pop();
          },
          child: Text('curator.sign_in_screen_remote_code_skip'.tr()),
        ),
        ElevatedButton(
          onPressed: remoteCodeLoading.value ? null : checkRemoteAccessCode,
          child: remoteCodeLoading.value
              ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : Text('curator.sign_in_screen_remote_code_verify'.tr()),
        ),
      ],
    );
  }
}

/// Show modal dialog for remote code input
Future<void> showRemoteCodeModal(
  BuildContext context,
  Future<void> Function() getRemoteDevices,
  void Function(ApiErrorMessage, Object) handleError,
  Future<void> Function() initiateRemoteAccess,
) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => RemoteCodeModal(
      getRemoteDevices: getRemoteDevices,
      handleError: handleError,
      initiateRemoteAccess: initiateRemoteAccess,
    ),
  );
}
