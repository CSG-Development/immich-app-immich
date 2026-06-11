import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/network/prompt_remote_access_auth.dart';
import 'package:logging/logging.dart';

final remoteAccessAuthServiceProvider = Provider<RemoteAccessAuthService>(
  (ref) => RemoteAccessAuthService(ref),
);

class RemoteAccessAuthService {
  RemoteAccessAuthService(this._ref);

  final Ref _ref;
  final Logger _log = Logger('RemoteAccessAuthService');

  bool get isAuthenticated => _ref.read(remoteProvider).isAuthenticated;

  Future<bool> promptAndRetry(Future<void> Function() retry) async {
    _log.info(
      '[OTP] promptAndRetry start '
      'remoteAuth=$isAuthenticated '
      'deviceLogin=${_ref.read(deviceProvider).login ?? '-'}',
    );
    if (isAuthenticated) {
      _log.info('[OTP] promptAndRetry fast-path already authenticated, running retry');
      await retry();
      return true;
    }

    final context = _ref.read(appRouterProvider).navigatorKey.currentContext;
    if (context == null || !context.mounted) {
      _log.warning('[OTP] promptAndRetry abort reason=navigator_context_unavailable');
      return false;
    }

    final deviceLogin = _ref.read(deviceProvider).login?.trim();
    final storedEmail = Store.tryGet(StoreKey.currentUser)?.email.trim() ?? '';
    final email = deviceLogin != null && deviceLogin.isNotEmpty ? deviceLogin : storedEmail;
    if (email.isEmpty) {
      _log.warning(
        '[OTP] promptAndRetry abort reason=no_email '
        'deviceLogin=${deviceLogin ?? '-'} storedEmail=${storedEmail.isEmpty ? '-' : storedEmail}',
      );
      return false;
    }

    _log.info('[OTP] showing modal email=$email skipInitialCodeSend=$isAuthenticated');
    final remoteOk = await promptRemoteAccessAuth(
      context: context,
      remoteProvider: _ref.read(remoteProvider.notifier),
      email: email,
      skipInitialCodeSend: isAuthenticated,
      onEmailNotAllowed: () {
        _log.warning('[OTP] email not allowed email=$email');
      },
    );
    if (!remoteOk) {
      _log.warning('[OTP] promptAndRetry modal closed without success email=$email');
      return false;
    }

    _log.info('[OTP] modal succeeded, running post-OTP retry');
    try {
      await retry();
      _log.info('[OTP] post-OTP retry completed remoteAuth=${_ref.read(remoteProvider).isAuthenticated}');
      return true;
    } catch (error, stackTrace) {
      _log.warning('[OTP] post-OTP retry failed', error, stackTrace);
      return false;
    }
  }
}
