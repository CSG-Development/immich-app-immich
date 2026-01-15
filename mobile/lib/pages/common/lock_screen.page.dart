import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/pages/security/lock_flow.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/secure_storage.service.dart';
import 'package:immich_mobile/widgets/common/splash_screen.dart';
import 'package:immich_mobile/widgets/security/local_auth_bottom_sheet.dart';
import 'package:immich_mobile/services/local_auth.service.dart';

@RoutePage()
class LockScreenPage extends HookConsumerWidget {
  const LockScreenPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {

    hideLockScreen() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        context.pop(true);
      });
    }

    void resumeSession() async {
      final enableBiometric = Store.tryGet(StoreKey.enableBiometric) ?? false;

      final enablePasscodeLock = (await ref.read(secureStorageServiceProvider).read(kSecuredPasscode)) != null;
      final enablePatternLock = (await ref.read(secureStorageServiceProvider).read(kSecuredPattern)) != null;

      final canAuthenticate = (await ref.read(localAuthServiceProvider).getStatus()).canAuthenticate;
      if (enableBiometric && canAuthenticate) {
        await showLocalAuthBottomSheet(context: context, onSuccess: hideLockScreen);
      } else if (enablePasscodeLock) {
        await context.pushRoute(PasscodeLockRoute(flow: LockFlow.validate, onSuccess: hideLockScreen));
      } else if (enablePatternLock) {
        await context.pushRoute(PatternLockRoute(flow: LockFlow.validate, onSuccess: hideLockScreen));
      } else {
        hideLockScreen();
      }
    }

    useEffect(() {
      resumeSession();
      return null;
    }, []);

    return const SplashScreen();
  }
}
