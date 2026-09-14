import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' show useEffect, useMemoized, useState;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/local_auth.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/forms/pin_registration_form.dart';
import 'package:immich_mobile/widgets/forms/pin_verification_form.dart';

@RoutePage()
class PinAuthPage extends HookConsumerWidget {
  final bool createPinCode;

  const PinAuthPage({super.key, this.createPinCode = false});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localAuthState = ref.watch(localAuthProvider);
    final showPinRegistrationForm = useState(createPinCode);
    // Resolve create vs verify after push so LockedGuard is not blocked on getAuthStatus.
    final isResolving = useState(!createPinCode);
    final pinFieldKey = useMemoized(GlobalKey.new);
    final keyboardInset = MediaQuery.viewInsetsOf(context).bottom;

    useEffect(() {
      if (createPinCode) {
        return null;
      }

      var cancelled = false;
      unawaited(() async {
        try {
          final api = ref.read(apiServiceProvider);
          final status = await api.authenticationApi.getAuthStatus();
          if (cancelled || status == null) {
            return;
          }
          if (status.isElevated) {
            unawaited(api.authenticationApi.lockAuthSession().catchError((_) {}));
          }
          showPinRegistrationForm.value = !status.pinCode;
        } finally {
          if (!cancelled) {
            isResolving.value = false;
          }
        }
      }());

      return () => cancelled = true;
    }, [createPinCode]);

    // Scroll PIN into view when the keyboard opens (esp. landscape).
    useEffect(() {
      if (isResolving.value || keyboardInset == 0) {
        return null;
      }

      WidgetsBinding.instance.addPostFrameCallback((_) {
        final fieldContext = pinFieldKey.currentContext;
        if (fieldContext == null) {
          return;
        }
        Scrollable.ensureVisible(
          fieldContext,
          duration: const Duration(milliseconds: 250),
          curve: Curves.easeOut,
          alignment: 0.2,
        );
      });
      return null;
    }, [keyboardInset > 0, isResolving.value, showPinRegistrationForm.value]);

    Future<void> registerBiometric(String pinCode) async {
      final isRegistered = await ref.read(localAuthProvider.notifier).registerBiometric(context, pinCode);

      if (isRegistered) {
        context.showSnackBar(
          SnackBar(
            content: Text('biometric_auth_enabled'.tr(), style: context.textTheme.labelLarge),
            duration: const Duration(seconds: 3),
            backgroundColor: context.colorScheme.primaryContainer,
          ),
        );

        unawaited(context.replaceRoute(const DriftLockedFolderRoute()));
      }
    }

    enableBiometricAuth() {
      showDialog(
        context: context,
        builder: (buildContext) {
          return SimpleDialog(
            children: [
              Container(
                padding: const EdgeInsets.all(16),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    PinVerificationForm(
                      description: 'enable_biometric_auth_description'.tr(),
                      onSuccess: (pinCode) {
                        Navigator.pop(buildContext);
                        registerBiometric(pinCode);
                      },
                      autoFocus: true,
                      icon: Icons.fingerprint_rounded,
                      successIcon: Icons.fingerprint_rounded,
                    ),
                  ],
                ),
              ),
            ],
          );
        },
      );
    }

    Future<void> popAfterKeyboard() async {
      FocusManager.instance.primaryFocus?.unfocus();
      for (var i = 0; i < 8; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 50));
        if (!context.mounted || MediaQuery.viewInsetsOf(context).bottom == 0) {
          break;
        }
      }
      if (context.mounted) {
        await context.router.maybePop();
      }
    }

    return PopScope(
      canPop: MediaQuery.viewInsetsOf(context).bottom == 0,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) {
          unawaited(popAfterKeyboard());
        }
      },
      child: Scaffold(
        resizeToAvoidBottomInset: false,
        appBar: AppBar(title: Text('locked_folder'.tr())),
        body: isResolving.value
            ? const Center(child: CircularProgressIndicator())
            : ListView(
                // Manual inset padding: avoids Scaffold resize jank but keeps landscape scrollable.
                padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 36.0),
                    child: showPinRegistrationForm.value
                        ? Center(
                            child: KeyedSubtree(
                              key: pinFieldKey,
                              child: PinRegistrationForm(onDone: () => showPinRegistrationForm.value = false),
                            ),
                          )
                        : Column(
                            children: [
                              Center(
                                child: KeyedSubtree(
                                  key: pinFieldKey,
                                  child: PinVerificationForm(
                                    autoFocus: true,
                                    onSuccess: (_) {
                                      context.replaceRoute(const DriftLockedFolderRoute());
                                    },
                                  ),
                                ),
                              ),
                              const SizedBox(height: 24),
                              if (localAuthState.canAuthenticate) ...[
                                Padding(
                                  padding: const EdgeInsets.only(right: 16.0),
                                  child: TextButton.icon(
                                    icon: const Icon(Icons.fingerprint, size: 28),
                                    onPressed: enableBiometricAuth,
                                    label: Text(
                                      'use_biometric'.tr(),
                                      style: context.textTheme.labelLarge?.copyWith(
                                        color: context.primaryColor,
                                        fontSize: 18,
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                  ),
                ],
              ),
      ),
    );
  }
}
