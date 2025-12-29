import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/utils/background_sync.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/auth/login_response.model.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/app_settings.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/repositories/auth.repository.dart';
import 'package:immich_mobile/repositories/auth_api.repository.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:logging/logging.dart';

final authServiceProvider = Provider(
  (ref) => AuthService(
    ref.watch(authApiRepositoryProvider),
    ref.watch(authRepositoryProvider),
    ref.watch(apiServiceProvider),
    ref.watch(backgroundSyncProvider),
    ref.watch(appSettingsServiceProvider),
  ),
);

class AuthService {
  final AuthApiRepository _authApiRepository;
  final AuthRepository _authRepository;
  final ApiService _apiService;
  final BackgroundSyncManager _backgroundSyncManager;
  final AppSettingsService _appSettingsService;
  final _log = Logger("AuthService");

  AuthService(
    this._authApiRepository,
    this._authRepository,
    this._apiService,
    this._backgroundSyncManager,
    this._appSettingsService,
  );

  /// Validates the provided server URL by resolving and setting the endpoint.
  /// Also sets the device info header and stores the valid URL.
  ///
  /// [url] - The server URL to be validated.
  ///
  /// Returns the validated and resolved server URL as a [String].
  ///
  /// Throws an exception if the URL cannot be resolved or set.
  Future<String> validateServerUrl(String url) async {
    final validUrl = await _apiService.resolveAndSetEndpoint(url);
    await _apiService.setDeviceInfoHeader();
    // Store.put(StoreKey.serverUrl, validUrl);

    return validUrl;
  }

  Future<LoginResponse> login(String email, String password) {
    return _authApiRepository.login(email, password);
  }

  /// Performs user logout operation by making a server request and clearing local data.
  ///
  /// This method attempts to log out the user through the authentication API repository.
  /// If the server request fails, the error is logged but local data is still cleared.
  /// The local data cleanup is guaranteed to execute regardless of the server request outcome.
  ///
  /// Throws any unhandled exceptions from the API request or local data clearing operations.
  Future<void> logout() async {
    try {
      await _authApiRepository.logout();
    } catch (error, stackTrace) {
      _log.severe("Error logging out", error, stackTrace);
    } finally {
      await clearLocalData().catchError((error, stackTrace) {
        _log.severe("Error clearing local data", error, stackTrace);
      });

      await _appSettingsService.setSetting(AppSettingsEnum.enableBackup, false);
    }
  }

  /// Clears all local authentication-related data.
  ///
  /// This method performs a concurrent deletion of:
  /// - Authentication repository data
  /// - Current user information
  /// - Access token
  /// - Asset ETag
  ///
  /// All deletions are executed in parallel using [Future.wait].
  Future<void> clearLocalData() async {
    // Cancel any ongoing background sync operations before clearing data
    await _backgroundSyncManager.cancel();
    await Future.wait([
      _authRepository.clearLocalData(),
      Store.delete(StoreKey.currentUser),
      Store.delete(StoreKey.accessToken),
      Store.delete(StoreKey.assetETag),
      Store.delete(StoreKey.autoEndpointSwitching),
      Store.delete(StoreKey.preferredWifiName),
      Store.delete(StoreKey.localEndpoint),
      Store.delete(StoreKey.externalEndpointList),
    ]);
  }

  Future<void> changePassword(String newPassword) {
    try {
      return _authApiRepository.changePassword(newPassword);
    } catch (error, stackTrace) {
      _log.severe("Error changing password", error, stackTrace);
      rethrow;
    }
  }

  Future<bool> unlockPinCode(String pinCode) {
    return _authApiRepository.unlockPinCode(pinCode);
  }

  Future<void> lockPinCode() {
    return _authApiRepository.lockPinCode();
  }

  Future<void> setupPinCode(String pinCode) {
    return _authApiRepository.setupPinCode(pinCode);
  }
}
