import 'dart:io';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/pages/security/lock_flow.dart';
import 'package:immich_mobile/providers/local_auth.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/secure_storage.service.dart';

class LocalAuthBottomSheet extends HookConsumerWidget {
  const LocalAuthBottomSheet({super.key, required this.onSuccess});

  final VoidCallback onSuccess;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final hasPasscodeLock = useState(false);
    final hasPatternLock = useState(false);
    final isAuthSuccess = useState(false);
    final isAuthError = useState(false);

    useEffect(() {
      Future.wait([
        ref.read(secureStorageServiceProvider).read(kSecuredPasscode),
        ref.read(secureStorageServiceProvider).read(kSecuredPattern),
      ]).then((result) {
        final [hasPasscodeLockResult, hasPatternLockResult] = result;
        hasPasscodeLock.value = hasPasscodeLockResult != null;
        hasPatternLock.value = hasPatternLockResult != null;
      });
      return null;
    }, []);

    void onAuthSuccess() async {
      isAuthSuccess.value = true;
      await Future.delayed(const Duration(milliseconds: 500));
      context.pop();
      onSuccess();
    }

    void onAuth() async {
      final authSuccess = await ref.read(localAuthProvider.notifier).authenticate(context, null);
      if (authSuccess) {
        onAuthSuccess();
      } else {
        isAuthError.value = true;
      }
    }

    useEffect(() {
      onAuth();
      return null;
    }, []);

    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(
            height: 72,
            child: Center(
              child: SvgPicture.asset(
                context.isDarkTheme ? 'assets/curator-photos-logo-dark.svg' : 'assets/curator-photos-logo-light.svg',
                height: 18,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsetsGeometry.symmetric(horizontal: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Center(
                  child: Text(
                    'curator.local_auth_sign_in'.tr(),
                    style: context.textTheme.bodyLarge?.copyWith(fontSize: 20, fontWeight: FontWeight.w400),
                  ),
                ),
                const SizedBox(height: 12.0),
                Center(
                  child: GestureDetector(
                    onTap: onAuth,
                    child: isAuthSuccess.value
                        ? SvgPicture.asset('assets/biom-auth-success.svg', height: 84.0)
                        : isAuthError.value
                        ? SvgPicture.asset('assets/biom-auth-error.svg', height: 84.0)
                        : Platform.isIOS
                        ? SvgPicture.asset('assets/biom-auth-fi.svg', height: 84.0)
                        : SvgPicture.asset('assets/biom-auth-fp.svg', height: 84.0),
                  ),
                ),
                const SizedBox(height: 12.0),
                if (hasPasscodeLock.value || hasPatternLock.value)
                  Padding(
                    padding: const EdgeInsetsGeometry.symmetric(vertical: 15.0, horizontal: 12.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (hasPasscodeLock.value) ...[
                          GestureDetector(
                            onTap: () =>
                                context.pushRoute(PasscodeLockRoute(flow: LockFlow.validate, onSuccess: onAuthSuccess)),
                            child: Text(
                              "curator.local_auth_use_passcode".tr(),
                              style: TextStyle(color: context.themeData.primaryColor, fontWeight: FontWeight.w500),
                            ),
                          ),
                          const SizedBox(height: 12),
                        ],
                        if (hasPatternLock.value)
                          GestureDetector(
                            onTap: () =>
                                context.pushRoute(PatternLockRoute(flow: LockFlow.validate, onSuccess: onAuthSuccess)),
                            child: Text(
                              "curator.local_auth_use_pattern".tr(),
                              style: TextStyle(color: context.themeData.primaryColor, fontWeight: FontWeight.w500),
                            ),
                          ),
                      ],
                    ),
                  )
                else
                  const SizedBox(height: 46),
                const SizedBox(height: 16),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Future<void> showLocalAuthBottomSheet({required BuildContext context, required VoidCallback onSuccess}) async {
  await showModalBottomSheet(
    backgroundColor: context.colorScheme.surfaceBright,
    isScrollControlled: false,
    isDismissible: false,
    enableDrag: false,
    showDragHandle: false,
    context: context,
    builder: (context) {
      return PopScope(canPop: false, child: LocalAuthBottomSheet(onSuccess: onSuccess));
    },
  );
}
