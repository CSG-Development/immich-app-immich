import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:homecloud_frontend/api/remote_access.swagger.dart';
import 'package:homecloud_frontend/providers/hcdevice.provider.dart';
import 'package:homecloud_frontend/utils.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class ActionItem {
  final String label;
  final VoidCallback onPressed;
  final bool isEnabled;
  final bool isLoading;
  final bool isDisabled;
  final bool isVisible;
  ActionItem({
    required this.label,
    required this.onPressed,
    this.isEnabled = true,
    this.isLoading = false,
    this.isDisabled = false,
    this.isVisible = true,
  });
}

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
        }
      }
      remoteCodeLoading.value = false;
    }

    List<ActionItem> actions = [
      ActionItem(
        label: 'curator.sign_in_screen_remote_code_skip'.tr(),
        onPressed: () {
          Navigator.of(context).pop();
          onSuccess();
        },
        isEnabled: true,
        isLoading: false,
        isDisabled: false,
        isVisible: true,
      ),
      ActionItem(
        label: 'curator.sign_in_screen_remote_code_verify'.tr(),
        onPressed: checkRemoteAccessCode,
        isEnabled: true,
        isLoading: remoteCodeLoading.value,
        isDisabled: false,
        isVisible: true,
      ),
    ];

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
              // helperText: 'curator.sign_in_screen_field_remote_code_hint'.tr(),
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
            autofocus: true,
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
      actions: actions
          .where((action) => action.isVisible)
          .map((action) => TextButton(
                onPressed: action.onPressed,
                style: TextButton.styleFrom(
                  minimumSize: Size.zero,
                  padding: const EdgeInsets.all(12.0),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
                child: Text(action.label),
              ))
          .toList(),
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
