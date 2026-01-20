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

import 'dart:convert' show base64Encode, jsonEncode, jsonDecode;
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
import 'package:homecloud_frontend/api/remote_access.swagger.dart'
    show DevicePath;
import 'package:homecloud_frontend/providers/auth.api.dart';
import 'package:http/io_client.dart' show IOClient;
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesAsync;

class DeviceProvider with ChangeNotifier implements CuratorAuthProvider {
  static const String basePath = '/api/v1';
  static const String loginKey = "curator_login";
  static const String favoriteDeviceKey = "curator_favorite";
  static const String favoriteDevicePathsKey = "curator_favorite_paths";
  static const String refreshTokenKey = "curator_refresh_token";

  static String productName = const String.fromEnvironment(
    'PRODUCT_NAME',
    defaultValue: 'Curator',
  );

  /// To store non-critical info (like login, favorite device id, etc)
  final Map<String, dynamic> storageData;

  /// To store sensitive info about the device (like refresh token)
  final FlutterSecureStorage secureStorage;

  static X509CertificateData? defaultCertificate;
  final X509CertificateData deviceCertificate;

  /// The base URL for the device API
  Uri? _baseUrl;
  Api? _api;

  /// The tokens for authentication
  String? _accessToken, _refreshToken;

  /// The email identifier for the user
  String? _login;

  /// The device ID, corresponds to the certificate common name
  String? _deviceID;

  /// The status of the device to manage routing
  Status? _deviceStatus;

  /// The paths of the device to connect to
  List<DevicePath>? _devicePaths;

  /// Flag to force re-detection of the device (with the Sign In screen)
  bool forceDetectFavoriteDevice = false;

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
    
    // Load device paths from storage
    final pathsJson = storageData[favoriteDevicePathsKey];
    if (pathsJson != null && pathsJson is String) {
      try {
        final List<dynamic> pathsList = jsonDecode(pathsJson);
        _devicePaths = pathsList
            .map((e) => DevicePath.fromJson(e as Map<String, dynamic>))
            .toList();
      } catch (e) {
        if (kDebugMode) {
          print("[DeviceProvider] Error loading device paths: ${e.toString()}");
        }
        _devicePaths = null;
      }
    }
    
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
  
  /// The device paths (local, public, relay) for connecting to the device.
  /// Available for remote devices.
  List<DevicePath>? get devicePaths => _devicePaths;

  /// Sets the host configuration for the device provider.
  ///
  /// This method updates the base URL, authentication tokens, and API instance.
  /// Optionally, it saves the authentication and notifies listeners about the change.
  ///
  /// Parameters:
  /// - [host]: The host address as a string. Used to create the base URL if [baseUrl] is not provided.
  /// - [baseUrl]: The base URL as a [Uri]. If null, it is created from [host].
  /// - [auth]: The authentication response containing access and refresh tokens.
  /// - [login]: The login identifier for the user. Used to save the login in shared preferences.
  /// - [status]: The status of the device to manage routing.
  /// - [deviceID]: The device ID, corresponds to the certificate common name.
  /// - [productName]: The model name of the device.
  /// - [save]: If true (default), authentication details are saved in persistent storage.
  void setHost({
    String? host,
    int? port,
    Uri? baseUrl,
    AuthResponse? auth,
    String? login,
    Status? status,
    String? deviceID,
    List<DevicePath>? devicePaths,
    String? productName,
    bool save = true,
  }) {
    if (baseUrl != null || host != null) {
      forceDetectFavoriteDevice = false;
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
    }
    if (login != null) {
      _login = login;
    }
    if (status != null) {
      _deviceStatus = status;
    }
    if (deviceID != null) {
      _deviceID = deviceID;
    }
    if (productName != null) {
      DeviceProvider.productName = productName;
    }
    if (devicePaths != null) {
      _devicePaths = devicePaths;
    }
    if (save) {
      _saveAuthentication(deviceID: deviceID, auth: auth, login: login, devicePaths: devicePaths);
    }
    // Warning: Do not notify listeners here to avoid multiple redirects with GoRouter
  }

  void _saveAuthentication({
    String? deviceID,
    AuthResponse? auth,
    String? login,
    List<DevicePath>? devicePaths,
  }) {
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    // Save favorite device in shared preferences
    if (deviceID != null) {
      asyncPrefs.setString(favoriteDeviceKey, deviceID);
    }
    // Save/Clear device paths in shared preferences
    if (devicePaths != null) {
      if (devicePaths.isNotEmpty) {
        try {
          final pathsJson = jsonEncode(
            devicePaths.map((path) => path.toJson()).toList(),
          );
          asyncPrefs.setString(favoriteDevicePathsKey, pathsJson);
        } catch (e) {
          if (kDebugMode) {
            print("[DeviceProvider] Error saving device paths: ${e.toString()}");
          }
        }
      } else {
        // Clear paths if explicitly set to empty list
        asyncPrefs.remove(favoriteDevicePathsKey);
      }
    }
    // Save refresh token in secure storage
    if (auth?.refreshToken != null) {
      try {
        secureStorage.write(key: refreshTokenKey, value: auth?.refreshToken);
      } catch (e) {
        if (kDebugMode) {
          print("[DeviceProvider] Error saving refresh token: ${e.toString()}");
        }
      }
    }
    // Save login in shared preferences
    if (login != null) {
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
    clearDevice();
    notifyListeners();
  }

  void clearDevice({save = false}) {
    _baseUrl = null;
    _api = null;
    _deviceStatus = null;
    _deviceID = null;
    _devicePaths = null;
    if (save == true) {
      _saveAuthentication(deviceID: _deviceID, devicePaths: _devicePaths);
      notifyListeners();
    }
  }

  void forceToRedetectDevice() {
    clearDevice();
    forceDetectFavoriteDevice = true;
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
