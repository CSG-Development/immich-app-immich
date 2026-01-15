import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/pages/security/lock_flow.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:immich_mobile/services/secure_storage.service.dart';
import 'package:immich_mobile/utils/hooks/add_biometric_auth_hook.dart';
import 'package:immich_mobile/utils/hooks/app_settings_update_hook.dart';

enum _PasscodeStage { verifyExisting, createNew, confirmNew }

@RoutePage()
class PasscodeLockPage extends HookConsumerWidget {
  const PasscodeLockPage({super.key, this.flow = LockFlow.validate, this.onSuccess});

  final LockFlow flow;
  final VoidCallback? onSuccess;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final secureStorage = ref.watch(secureStorageServiceProvider);

    final stage = useState<_PasscodeStage>(
      flow == LockFlow.create ? _PasscodeStage.createNew : _PasscodeStage.verifyExisting,
    );
    final enteredPasscode = useState<String>('');
    final firstEntry = useState<String?>(null);
    final hasError = useState<bool>(false);
    final isLoading = useState<bool>(false);

    final enableBiometric = useAppSettingsState(AppSettingsEnum.enableBiometric);
    final handleAddBiometric = useAddBiometricAuthHook(context, ref);

    Future<void> handleCompleted(String input) async {
      if (isLoading.value) return;

      switch (stage.value) {
        case _PasscodeStage.verifyExisting:
          isLoading.value = true;
          try {
            final savedPasscode = await secureStorage.read(kSecuredPasscode);

            if (savedPasscode == null || savedPasscode != input) {
              hasError.value = true;
              enteredPasscode.value = '';
              return;
            }

            if (flow == LockFlow.remove) {
              await secureStorage.delete(kSecuredPasscode);
            }

            context.maybePop(true);
            onSuccess?.call();
          } finally {
            isLoading.value = false;
          }
          break;
        case _PasscodeStage.createNew:
          firstEntry.value = input;
          enteredPasscode.value = '';
          hasError.value = false;
          stage.value = _PasscodeStage.confirmNew;
          break;
        case _PasscodeStage.confirmNew:
          if (firstEntry.value == input) {
            isLoading.value = true;
            try {
              await secureStorage.write(kSecuredPasscode, input);

              if (!enableBiometric.value) {
                final shouldEnableBiometric = await handleAddBiometric();
                if (shouldEnableBiometric) {
                  enableBiometric.value = shouldEnableBiometric;
                }
              }

              context.maybePop(true);
            } finally {
              isLoading.value = false;
            }
          } else {
            hasError.value = true;
            enteredPasscode.value = '';
          }
          break;
      }
    }

    void onDigitTap(String digit) {
      if (enteredPasscode.value.length >= 4 || isLoading.value) return;
      hasError.value = false;
      final next = '${enteredPasscode.value}$digit';
      enteredPasscode.value = next;
      if (next.length == 4) {
        handleCompleted(next);
      }
    }

    void onBackspace() {
      if (enteredPasscode.value.isEmpty || isLoading.value) return;
      hasError.value = false;
      enteredPasscode.value = enteredPasscode.value.substring(0, enteredPasscode.value.length - 1);
    }

    String getTitle() {
      switch (stage.value) {
        case _PasscodeStage.verifyExisting:
          return flow == LockFlow.remove ? 'curator.passcode_remove_title'.tr() : 'curator.passcode_enter_title'.tr();
        case _PasscodeStage.createNew:
          return 'curator.passcode_create_title'.tr();
        case _PasscodeStage.confirmNew:
          return 'curator.passcode_confirm_title'.tr();
      }
    }

    String getSubtitle() {
      switch (stage.value) {
        case _PasscodeStage.verifyExisting:
          return 'curator.passcode_enter_subtitle'.tr();
        case _PasscodeStage.createNew:
          return 'curator.passcode_create_subtitle'.tr();
        case _PasscodeStage.confirmNew:
          return 'curator.passcode_confirm_subtitle'.tr();
      }
    }

    String getError() {
      switch (stage.value) {
        case _PasscodeStage.verifyExisting:
          return 'curator.passcode_enter_error'.tr();
        case _PasscodeStage.createNew:
          return 'curator.passcode_create_error'.tr();
        case _PasscodeStage.confirmNew:
          return 'curator.passcode_confirm_error'.tr();
      }
    }

    handleLogout() {
      ref.read(authProvider.notifier).logout();
      context.replaceRoute(const LoginRoute());
    }

    return PopScope(
      canPop: flow != LockFlow.validate,
      onPopInvokedWithResult: (didPop, result) {
        if (!didPop && result == true) {
          Navigator.of(context).pop();
        }
      },
      child: Scaffold(
        appBar: AppBar(
          centerTitle: false,
          title: Text('curator.passcode_title'.tr()),
          automaticallyImplyLeading: flow != LockFlow.validate,
        ),
        body: SafeArea(
          child: Column(
            children: [
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      getTitle(),
                      style: context.textTheme.titleMedium?.copyWith(fontSize: 16, fontWeight: FontWeight.w500),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 12),
                    if (getSubtitle().isNotEmpty) ...[
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          getSubtitle(),
                          style: context.textTheme.bodyMedium?.copyWith(
                            color: context.colorScheme.onSurfaceVariant,
                            fontSize: 14,
                            fontWeight: FontWeight.w400,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    _PasscodeDots(length: 4, filled: enteredPasscode.value.length, hasError: hasError.value),
                    if (hasError.value) ...[
                      const SizedBox(height: 12),
                      Text(
                        getError(),
                        style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.error, fontSize: 16),
                        textAlign: TextAlign.center,
                      ),
                    ],
                    const SizedBox(height: 40),
                    _PasscodeKeypad(onDigitTap: onDigitTap, onBackspace: onBackspace, isLoading: isLoading.value),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
              if (flow == LockFlow.validate && hasError.value)
                GestureDetector(
                  onTap: handleLogout,
                  child: Text(
                    "log_out".tr(),
                    style: TextStyle(color: context.themeData.primaryColor, fontWeight: FontWeight.w500),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PasscodeDots extends StatelessWidget {
  const _PasscodeDots({required this.length, required this.filled, required this.hasError});

  final int length;
  final int filled;
  final bool hasError;

  @override
  Widget build(BuildContext context) {
    final color = hasError ? context.colorScheme.error : context.colorScheme.onSurface;

    return Row(
      mainAxisAlignment: MainAxisAlignment.center,
      children: List.generate(
        length,
        (index) => Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Container(
            width: 15,
            height: 15,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: index < filled ? color : null,
              border: Border.all(width: 1.5, color: color),
            ),
          ),
        ),
      ),
    );
  }
}

class _PasscodeKeypad extends StatelessWidget {
  const _PasscodeKeypad({required this.onDigitTap, required this.onBackspace, required this.isLoading});

  final void Function(String digit) onDigitTap;
  final VoidCallback onBackspace;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    final keys = <List<String?>>[
      ['1', '2', '3'],
      ['4', '5', '6'],
      ['7', '8', '9'],
      [null, '0', 'back'],
    ];

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 48),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (final row in keys) ...[
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: row.map((value) {
                if (value == null) {
                  return const Expanded(child: SizedBox(height: 72));
                }
                if (value == 'back') {
                  return Expanded(
                    child: _KeypadButton(
                      onTap: isLoading ? null : onBackspace,
                      child: Icon(Icons.backspace_outlined, size: 24.0, color: context.themeData.colorScheme.onSurface),
                    ),
                  );
                }
                return Expanded(
                  child: _KeypadButton(label: value, onTap: isLoading ? null : () => onDigitTap(value)),
                );
              }).toList(),
            ),
            const SizedBox(height: 16),
          ],
        ],
      ),
    );
  }
}

class _KeypadButton extends StatelessWidget {
  const _KeypadButton({this.label, this.child, this.onTap});

  final String? label;
  final Widget? child;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final content =
        child ??
        Text(
          label ?? '',
          style: context.textTheme.titleLarge?.copyWith(
            fontSize: 34,
            fontWeight: FontWeight.w700,
            color: context.themeData.colorScheme.onSurface.withAlpha(153),
          ),
        );

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(8),
        child: InkWell(
          borderRadius: BorderRadius.circular(40),
          onTap: onTap,
          child: Container(
            width: 64.0,
            height: 64.0,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: label == null ? null : context.colorScheme.primary.withAlpha(40),
            ),
            alignment: Alignment.center,
            child: content,
          ),
        ),
      ),
    );
  }
}
