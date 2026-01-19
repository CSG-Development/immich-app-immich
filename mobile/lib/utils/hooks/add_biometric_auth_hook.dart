import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/local_auth.provider.dart';

Future<bool> Function() useAddBiometricAuthHook(BuildContext context, WidgetRef ref) {
  final localAuthState = ref.watch(localAuthProvider);

  Future<bool> handleAddBiometric() async {
    if (!localAuthState.canAuthenticate) {
      return false;
    }

    final shouldEnableBiometric = await showDialog<bool>(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          // title: const Text('login_form_add_security_title').tr(),
          content: const Text('login_form_add_security_content').tr(),
          actions: <Widget>[
            TextButton(child: const Text('no').tr(), onPressed: () => Navigator.of(dialogContext).pop(false)),
            TextButton(child: const Text('common_yes').tr(), onPressed: () => Navigator.of(dialogContext).pop(true)),
          ],
        );
      },
    );

    if (shouldEnableBiometric != true) {
      return false;
    }

    final isAuthenticated = await ref.read(localAuthProvider.notifier).authenticate(context, null);

    return isAuthenticated;
  }

  return handleAddBiometric;
}
