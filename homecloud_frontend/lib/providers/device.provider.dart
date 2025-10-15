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

import 'dart:convert' show base64Encode;
import 'dart:io'
    show SecurityContext, HttpClient, X509Certificate;
import 'package:basic_utils/basic_utils.dart'
    show X509CertificateData, X509Utils;
import 'package:chopper/chopper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;
import 'package:homecloud_frontend/api/api.enums.swagger.dart'
    show AuthRefreshPost$RequestBodyGrantType;
import 'package:homecloud_frontend/api/api.swagger.dart'
    show
        Api,
        AuthRefreshPost$RequestBody,
        AuthResponse,
        Status,
        AuthLogoutPost$RequestBody;
import 'package:homecloud_frontend/providers/auth.api.dart';
import 'package:http/io_client.dart' show IOClient;
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesAsync;

class DeviceProvider with ChangeNotifier implements CuratorAuthProvider {
  static const String basePath = '/api/v1';
  static const String loginKey = "curator_login";
  static const String favoriteDeviceKey = "curator_favorite";
  static const String refreshTokenKey = "curator_refresh_token";

  final Map<String, dynamic> storageData;
  final FlutterSecureStorage secureStorage;
  static X509CertificateData? defaultCertificate;
  final X509CertificateData deviceCertificate;

  Uri? _baseUrl;
  Api? _api;
  String? _accessToken, _refreshToken;
  String? _login;

  /// The device ID, corresponds to the certificate common name
  String? _deviceID;
  Status? _deviceStatus;

  DeviceProvider(
    this.storageData,
    this.secureStorage,
    Map<String, String> secureData,
    this.deviceCertificate,
  ) {
    // Retrieve info from Storage...
    _login = storageData[loginKey];
    _deviceID = storageData[favoriteDeviceKey];
    _refreshToken = secureData[refreshTokenKey];
    defaultCertificate ??= deviceCertificate;
  }

  Uri get baseUrl => _baseUrl!;
  Api get api => _api!;
  bool get deviceFound => _baseUrl != null;
  bool get isAuthenticated => _accessToken != null || _refreshToken != null;
  String get login => _login ?? '';
  @override
  String? get accessToken => _accessToken;

  /// The device ID, corresponds to the certificate common name
  String? get deviceID => _deviceID;
  Status? get deviceStatus => _deviceStatus;

  /// Sets the host configuration for the device provider.
  ///
  /// This method updates the base URL, authentication tokens, and API instance.
  /// Optionally, it saves the authentication and notifies listeners about the change.
  ///
  /// Parameters:
  /// - [host]: The host address as a string. Used to create the base URL if [baseUrl] is not provided.
  /// - [port]: The port number as an integer. Used in conjunction with [host] to create the base URL.
  /// - [baseUrl]: The base URL as a [Uri]. If null, it is created from [host].
  /// - [auth]: The authentication response containing access and refresh tokens.
  /// - [refreshToken]: The refresh token for authentication. Used if [auth] is not provided.
  /// - [login]: The login identifier for the user. Used to save the login in shared preferences.
  /// - [status]: The status of the device to manage routing.
  /// - [deviceID]: The device ID, corresponds to the certificate common name.
  /// - [save]: If true (default), authentication details are saved in persistent storage.
  void setHost({
    String? host,
    int? port,
    Uri? baseUrl,
    AuthResponse? auth,
    String? refreshToken,
    String? login,
    Status? status,
    String? deviceID,
    bool save = true,
  }) {
    if (baseUrl != null || host != null) {
      _baseUrl = baseUrl ?? createBaseUrl(host!, port);
      _api = createApi(
        baseUrl: _baseUrl!,
        authenticator: CuratorAuthenticator(this),
        interceptors: [CuratorInterceptor(this)],
      );
    }
    if (auth?.accessToken != null) {
      _accessToken = auth?.accessToken;
    }
    if (auth?.refreshToken != null) {
      _refreshToken = auth?.refreshToken;
    } else if (refreshToken != null) {
      _refreshToken = refreshToken;
    }
    if (status != null) {
      _deviceStatus = status;
    }
    if (deviceID != null) {
      _deviceID = deviceID;
    }
    if (save) {
      _saveAuthentication(deviceID: deviceID, auth: auth, login: login);
    }
    notifyListeners();
  }

  /// Save authentication details in persistent storage.
  void _saveAuthentication({
    String? deviceID,
    AuthResponse? auth,
    String? login,
  }) {
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    // Save/Clear favorite device in shared preferences
    if (deviceID != null) {
      asyncPrefs.setString(favoriteDeviceKey, deviceID);
    }
    // Save/Clear refresh token in secure storage
    try {
      if (auth?.refreshToken != null) {
        secureStorage.write(key: refreshTokenKey, value: auth?.refreshToken);
      } else {
        secureStorage.delete(key: refreshTokenKey);
      }
    } catch (e) {
      if (kDebugMode) {
        print("[DeviceProvider] Error saving bearer token: ${e.toString()}");
      }
    }
    // Save login in shared preferences
    if (login != null) {
      _login = login;
      asyncPrefs.setString(loginKey, login);
    }
  }

  @override
  bool isRefreshRequest(Request? request) {
    return request?.url.path.contains('/auth/refresh') ?? false;
  }

  void setDeviceStatus(Status status) {
    _deviceStatus = status;
    notifyListeners();
  }

  @override
  Future<String> refreshAccessToken() async {
    try {
      final response = await api.authRefreshPost(
        body: AuthRefreshPost$RequestBody(
          grantType: AuthRefreshPost$RequestBodyGrantType.refreshToken,
          refreshToken: _refreshToken!,
        ),
      );
      if (response.isSuccessful) {
        _accessToken = response.body?.accessToken;
        _refreshToken = response.body?.refreshToken;
        _saveAuthentication(auth: response.body);
        return _accessToken ?? '';
      } else {
        throw response.error ?? 'Refresh token error';
      }
    } catch (e) {
      if (kDebugMode) {
        print("[DeviceProvider] Error refreshing token: ${e.toString()}");
      }
      rethrow;
    }
  }

  @override
  Future<void> logout() async {
    // Clear persistent storage
    try {
      secureStorage.delete(key: refreshTokenKey);
    } catch (e) {
      if (kDebugMode) {
        print(
          "[DeviceProvider] Error clearing secure storage: ${e.toString()}",
        );
      }
    }
    // Invalidate the refresh token on the backend
    try {
      final AuthLogoutPost$RequestBody data = AuthLogoutPost$RequestBody(
        refreshToken: _refreshToken!,
      );
      final response = await api.authLogoutPost(body: data);
      if (response.isSuccessful) {
        if (kDebugMode) {
          print("[DeviceProvider] authLogoutPost successful");
        }
      } else {
        if (kDebugMode) {
          print("[DeviceProvider] authLogoutPost failed: ${response.error}");
        }
      }
    } catch (e) {
      if (kDebugMode) {
        print("[DeviceProvider] Error during logout API call: ${e.toString()}");
      }
    }
    _accessToken = null;
    _refreshToken = null;
    _baseUrl = null;
    _api = null;
    notifyListeners();
  }

  static Uri createBaseUrl(String host, int? port) {
    // Fix mDNS on iOS, the hostname could be "HomeCloud-5022166.local."
    if (host.endsWith(".")) {
      host = host.substring(0, host.length - 1);
    }
    if (port != null && port > 0) {
      host += ':$port';
    }
    Uri uri = Uri.https(host, basePath);
    return uri;
  }

  static Api createApi({
    required Uri baseUrl,
    Authenticator? authenticator,
    List<Interceptor>? interceptors,
  }) {
    return Api.create(
      httpClient: CuratorHttpClient(defaultCertificate!),
      baseUrl: baseUrl,
      authenticator: authenticator,
      interceptors: interceptors,
    );
  }
}

/// Override HttpClient to accept certificates signed by our root CA
class CuratorHttpClient extends IOClient {
  final X509CertificateData rootCertificate;

  CuratorHttpClient(this.rootCertificate)
    : super(_createClient(rootCertificate));

  static HttpClient _createClient(X509CertificateData rootCertificate) {
    List<X509CertificateData> rootCertificatesCopy = [rootCertificate];
    Map<String, bool> validCertificate = {};
    HttpClient client = HttpClient(context: SecurityContext.defaultContext);
    client.badCertificateCallback =
        (X509Certificate cert, String host, int port) => _checkCertificateChain(
          rootCertificatesCopy,
          validCertificate,
          cert,
          host,
          port,
        );
    return client;
  }

  /// Check if the certificate is valid by checking its chain with the Root CA certificate
  /// Caches the result for each host:port and certificate sha1 to avoid re-checking
  static bool _checkCertificateChain(
    List<X509CertificateData> rootCertificates,
    Map<String, bool> valideCertificate,
    X509Certificate cert,
    String host,
    int port,
  ) {
    bool isValid =
        valideCertificate[generateHostKey(host, port, cert.sha1)] ?? false;
    if (!isValid) {
      try {
        if (kDebugMode) {
          debugPrint(
            "[Certificate] Checking certificate for host: $host, port: $port",
          );
        }
        final X509CertificateData x509Data = X509Utils.x509CertificateFromPem(
          cert.pem,
        );
        if (kDebugMode) {
          debugPrint(
            "[Certificate] Parsed server certificate: ${x509Data.issuer}",
          );
        }
        // Check the chain with the Root CA certificate
        final chainCheckRootData = X509Utils.checkChain([
          x509Data,
          ...rootCertificates,
        ]);

        isValid = chainCheckRootData.isValid();
        if (isValid) {
          valideCertificate[generateHostKey(host, port, cert.sha1)] = true;
          // FIXME Try to manage intermediate certificates... (https://github.com/dart-lang/sdk/issues/59948)
          rootCertificates.add(x509Data);
        }
      } catch (e) {
        if (kDebugMode) {
          debugPrint(
            "[Certificate] Certificate parsing error: ${e.toString()}",
          );
        }
      }
    }
    return isValid;
  }

  static String generateHostKey(String host, int port, Uint8List certSha1) {
    return '$host:$port-${base64Encode(certSha1)}';
  }
}
