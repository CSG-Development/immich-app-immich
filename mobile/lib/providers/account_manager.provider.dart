
import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/constants.dart';
import 'package:immich_mobile/platform/account_manager_api.g.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:logging/logging.dart';

const keyOcAccountVersion = "oc_account_version";
const keyOcBaseUrl = "oc_base_url";
const keyOcDisplayName = "oc_display_name";
const keyOcEmail = "oc_email";
const keyOcId = "oc_id";
const keyIsKiteworksServer = "is_kiteworks_server";
const keyRaAccessToken = "ra_access_token";
const keyRaRefreshToken = "ra_refresh_token";
const keyRaFavoriteDeviceCertCommonName = "ra_favorite_device_cert_common_name";
const keyRaClientId = "ra_client_id";

class UserData {
  String? baseUrl;
  String? email;
  String? displayName;
  String? raAccessToken;
  String? raRefreshToken;
  String? raFavoriteDeviceCertCommonName;
  String? raClientId;

  UserData({
    this.baseUrl,
    this.email,
    this.displayName,
    this.raAccessToken,
    this.raRefreshToken,
    this.raFavoriteDeviceCertCommonName,
    this.raClientId,
  });

  factory UserData.fromMap(Map<String, String?> map) {
    return UserData(
      baseUrl: map[keyOcBaseUrl],
      email: map[keyOcEmail],
      displayName: map[keyOcDisplayName],
      raAccessToken: map[keyRaAccessToken],
      raRefreshToken: map[keyRaRefreshToken],
      raFavoriteDeviceCertCommonName: map[keyRaFavoriteDeviceCertCommonName],
      raClientId: map[keyRaClientId],
    );
  }

  Map<String, String?> toMap() {
    return {
      keyOcBaseUrl: baseUrl,
      keyOcEmail: email,
      keyOcDisplayName: displayName,
      keyRaAccessToken: raAccessToken,
      keyRaRefreshToken: raRefreshToken,
      keyRaFavoriteDeviceCertCommonName: raFavoriteDeviceCertCommonName,
      keyRaClientId: raClientId,
    };
  }
}

final accountManagerProvider = Provider<AccountManager>(
  (ref) => AccountManager(
    ref.watch(remoteProvider),
    ref.watch(deviceProvider),
    ref.watch(apiServiceProvider)
  ),
);

class AccountManager {
  final RemoteProvider _remoteProvider;
  final DeviceProvider _deviceProvider;
  final ApiService _apiService;

  final _accountManagerApi = AccountManagerApi();
  final Logger _log = Logger('AccountManager');

  AccountManager(
    this._remoteProvider,
    this._deviceProvider,
    this._apiService,
  ): super();


  Future<Account?> getSystemAccount() async {
    try {
      return (await _accountManagerApi.getAccounts()).firstOrNull;
    } catch (error, stackTrace) {
      _log.severe('Error getSystemAccount', error, stackTrace);
      return null;
    }
  }

  Future<void> setUserData(UserData userData) async {
    try {
      final account = await getSystemAccount();
      if (account != null) {
        await _accountManagerApi.setUserData(account, userData.toMap());
      }
    } catch (error, stackTrace) {
      _log.severe('Error setUserData', error, stackTrace);
    }
  }

  Future<void> createSystemAccount(String email, String password) async {
    try {
      var account = await getSystemAccount();
      if (account != null) {
        await _accountManagerApi.setPassword(account, password);
      }
      account ??= await _accountManagerApi.addAccount(Account(name: email, type: accountType), password);

      final accessToken = _remoteProvider.accessToken;
      final refreshToken = _remoteProvider.refreshToken;
      final clientId = _remoteProvider.clientId;
      final deviceID = _deviceProvider.deviceID;
      final basePath = _apiService.apiClient.basePath;

      await _accountManagerApi.setUserData(account, {
        keyOcAccountVersion: '',
        keyOcBaseUrl: basePath,
        keyOcDisplayName: email,
        keyOcEmail: email,
        keyOcId: '',
        keyIsKiteworksServer: '',
        keyRaAccessToken: accessToken,
        keyRaRefreshToken: refreshToken,
        keyRaFavoriteDeviceCertCommonName: deviceID,
        keyRaClientId: clientId,
      });
    } catch (error, stackTrace) {
      _log.severe('Error createSystemAccount', error, stackTrace);
    }
  }

  Future<String?> getSystemAccountPassword(Account account) async {
    try {
      return _accountManagerApi.getPassword(account);
    } catch (error, stackTrace) {
      _log.severe('Error getSystemAccountPassword', error, stackTrace);
      return null;
    }
  }

  Future<UserData?> getSystemAccountUserData(Account account) async {
    try {
      final userData = await _accountManagerApi.getUserData(account, [
        keyOcBaseUrl,
        keyOcEmail,
        keyRaAccessToken,
        keyRaRefreshToken,
        keyRaFavoriteDeviceCertCommonName,
        keyRaClientId
      ]);

      return UserData.fromMap(userData);
    } catch (error, stackTrace) {
      _log.severe('Error getSystemAccountUserData', error, stackTrace);
      return null;
    }
  }
}


final accountManagerUpdaterProvider = Provider<AccountManagerUpdater>((ref) {
  final listener = AccountManagerUpdater(ref);
  ref.onDispose(() => listener.dispose());
  return listener;
});

class AccountManagerUpdater {
  final Ref _ref;
  final Logger _log = Logger('AccountManagerUpdater');

  ProviderSubscription? _remoteProviderSubscription;

  AccountManagerUpdater(this._ref) {
    startListening();
  }

  void startListening() {
    _remoteProviderSubscription = _ref.listen<RemoteProvider>(remoteProvider, (
      RemoteProvider? previous,
      RemoteProvider? next,
    ) {
      if (next != null) {
        _ref
            .read(accountManagerProvider)
            .setUserData(UserData(raRefreshToken: next.refreshToken, raClientId: next.clientId));
      }
    });
  }

  void stopListening() {
    _log.info('Stopping RA change listener');
    _remoteProviderSubscription?.close();
    _remoteProviderSubscription = null;
  }

  void dispose() {
    _log.info('Disposing RAChangeListener and stopping listener');
    stopListening();
  }
}
