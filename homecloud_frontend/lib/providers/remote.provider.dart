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

import 'dart:io' show SecurityContext, HttpClient, X509Certificate;
import 'package:http/io_client.dart' show IOClient;
import 'package:basic_utils/basic_utils.dart' show StringUtils;
import 'package:chopper/chopper.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, kDebugMode;
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;
import 'package:homecloud_frontend/api/remote_access.swagger.dart'
    show RemoteAccess, TokenResponse$Response;
import 'package:homecloud_frontend/providers/auth.api.dart';
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesAsync;

class RemoteProvider with ChangeNotifier implements CuratorAuthProvider {
  /// TODO: replace with production URL
  /// TODO: remove HttpClient that accepts all certificates
  static const String baseUrl =
      'https://hc-remote-access-env-https.eba-a2nvhpbm.us-west-2.elasticbeanstalk.com:443/api';
  static const String refreshKey = 'curator_remote_refresh_token';
  static const String clientIdKey = 'curator_remote_client_id';

  String? _accessToken, _refreshToken, _reference;
  late String clientId;
  late RemoteAccess _api;

  final Map<String, dynamic> _storageData;
  final FlutterSecureStorage _secureStorage;

  RemoteProvider(
    this._storageData,
    this._secureStorage,
    Map<String, String> secureData,
  ) {
    _refreshToken = secureData[refreshKey];
    _initClientId(secureData);

    // FIXME for production!
    // Create an HttpClient that accepts the test server certificate
    HttpClient client = HttpClient(context: SecurityContext.defaultContext);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => true;

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
  bool get isAuthenticated => _accessToken != null || _refreshToken != null;
  String? get reference => _reference;
  RemoteAccess get api => _api;

  /// Initialize clientId with a unique, persistent identifier per device/app install
  void _initClientId(Map<String, String> secureData) {
    String? storedId = _storageData[clientIdKey];
    if (storedId != null) {
      clientId = storedId;
      if (kDebugMode) {
        print('[RemoteProvider] Using existing clientId: $clientId');
      }
    } else {
      clientId = StringUtils.generateRandomString(
        42,
        alphabet: true,
        numeric: true,
        special: false,
        uppercase: false,
        lowercase: true,
      );
      if (kDebugMode) {
        print('[RemoteProvider] Generated new clientId: $clientId');
      }
      final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
      asyncPrefs.setString(clientIdKey, clientId);
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
      final response = await api.clientV1AuthRefreshGet(
        refreshToken: _refreshToken!,
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
