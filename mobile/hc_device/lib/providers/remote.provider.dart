//   Do NOT modify or remove this copyright and confidentiality notice
//
//   Copyright (c) 2025 Seagate Technology LLC or one of its affiliates.
//
//   This code is classified as SEAGATE CONFIDENTIAL
//   and may be covered under one or more Non-Disclosure Agreements.
//   Any use, modification, duplication, derivation, distribution or disclosure
//   of this code, for any reason, not expressly authorized is prohibited.
//   All other rights are expressly reserved by Seagate Technology LLC.
//

import 'dart:io' show HttpClient, SecurityContext;
import 'package:http/io_client.dart' show IOClient;

import 'package:basic_utils/basic_utils.dart' show StringUtils;
import 'package:chopper/chopper.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, kDebugMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;
import 'package:hc_device/api/remote_access.swagger.dart'
    show RemoteAccess, TokenResponse$Response, Refresh$RequestBody;
import 'package:hc_device/providers/auth.api.dart';
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesAsync;

class RemoteProvider with ChangeNotifier implements CuratorAuthProvider {
  /// TODO: Replace with the production URL then remove HttpClient override
  @Deprecated("Replace with the production URL")
  static const String baseUrl =
      'https://hc-remote-access-env-https.eba-a2nvhpbm.us-west-2.elasticbeanstalk.com:443/api';
  static const String refreshKey = 'curator_remote_refresh_token';
  static const String clientIdKey = 'curator_remote_client_id';

  String? _accessToken, _refreshToken, _reference;
  late String _clientId;
  late RemoteAccess _api;

  final Map<String, dynamic> _storageData;
  final FlutterSecureStorage _secureStorage;

  RemoteProvider(
    this._storageData,
    this._secureStorage,
    Map<String, String> secureData,
  ) {
    _refreshToken = secureData[refreshKey];
    _initClientId();

    HttpClient client = HttpClient(context: SecurityContext.defaultContext);

    _api = RemoteAccess.create(
      baseUrl: Uri.parse(baseUrl),
      httpClient: IOClient(client),
      authenticator: CuratorAuthenticator(this),
      interceptors: [CuratorInterceptor(this)],
    );
  }

  @override
  String? get accessToken => _accessToken;
  String? get refreshToken => _refreshToken;
  String get clientId => _clientId;
  bool get isAuthenticated => _accessToken != null || _refreshToken != null;
  String? get reference => _reference;
  RemoteAccess get api => _api;

  /// Initialize clientId with a unique, persistent identifier per device/app install
  void _initClientId() {
    String? value = _storageData[clientIdKey];
    if (value != null) {
      _clientId = value;
      if (kDebugMode) {
        print('[RemoteProvider] Using existing clientId: $_clientId');
      }
    } else {
      _clientId = StringUtils.generateRandomString(
        42,
        alphabet: true,
        numeric: true,
        special: false,
        uppercase: false,
        lowercase: true,
      );
      if (kDebugMode) {
        print('[RemoteProvider] Generated new clientId: $_clientId');
      }
      final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
      asyncPrefs.setString(clientIdKey, _clientId);
    }
  }

  set reference(String? ref) {
    _reference = ref;
    notifyListeners();
  }

  void setAuthToken({
    required TokenResponse$Response auth,
    bool notify = true,
  }) {
    _accessToken = auth.accessToken;
    _refreshToken = auth.refreshToken;
    _saveRefreshToken(refreshToken: auth.refreshToken);
    if (notify) {
      notifyListeners();
    }
  }

  @override
  bool isRefreshRequest(Request? request) {
    return request?.url.path.contains('/auth/refresh') ?? false;
  }

  @override
  Future<String> refreshAccessToken() async {
    try {
      if (kDebugMode) {
        print('[RemoteProvider] Attempting to refresh access token...');
      }
      final response = await api.clientV1AuthRefreshPost(
        body: Refresh$RequestBody(
          clientId: _clientId,
          refreshToken: _refreshToken!,
        ),
      );
      if (kDebugMode) {
        print(
          '[RemoteProvider] Refresh response: statusCode=${response.statusCode}, isSuccessful=${response.isSuccessful}',
        );
      }
      if (response.isSuccessful) {
        final TokenResponse$Response data = response.body!;
        setAuthToken(auth: data, notify: false);
        return _accessToken ?? '';
      } else {
        throw response.error ?? 'Refresh token error';
      }
    } catch (e) {
      rethrow;
    }
  }

  /// Save or delete the refresh token in secure storage
  Future<void> _saveRefreshToken({String? refreshToken}) async {
    try {
      // Store refresh token securely
      if (refreshToken != null) {
        _secureStorage.write(key: refreshKey, value: refreshToken);
      } else {
        _secureStorage.delete(key: refreshKey);
      }
    } catch (e) {
      if (kDebugMode) {
        print("[RemoteProvider] Error saving bearer token: ${e.toString()}");
      }
    }
  }

  @override
  void logout() {
    _accessToken = null;
    _refreshToken = null;
    try {
      _secureStorage.delete(key: refreshKey);
    } catch (e) {
      if (kDebugMode) {
        print(
          "[RemoteProvider] Error clearing secure storage: ${e.toString()}",
        );
      }
    }
    notifyListeners();
  }
}
