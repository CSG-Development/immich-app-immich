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

import 'dart:convert' show jsonEncode, jsonDecode;
import 'package:chopper/chopper.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;
import 'package:hc_device/api/api.enums.swagger.dart'
    show AuthRefreshPost$RequestBodyGrantType;
import 'package:hc_device/api/api.swagger.dart'
    show
        Api,
        AuthRefreshPost$RequestBody,
        AuthResponse,
        Status,
        AuthLogoutPost$RequestBody;
import 'package:hc_device/api/remote_access.swagger.dart'
    show DevicePath, DevicePaths;
import 'package:hc_device/providers/auth.api.dart';
import 'package:hc_device/services/logger_service.dart';
import 'package:http/io_client.dart' show IOClient;
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesAsync;

class DeviceProvider with ChangeNotifier implements CuratorAuthProvider {
  static const String basePath = '/api/v1';
  static const String loginKey = "curator_login";
  static const String favoriteDeviceKey = "curator_favorite";
  static const String seagateDeviceIDKey = "curator_seagate_device_id";
  static const String favoriteDevicePathsKey = "curator_favorite_paths";
  static const String cachedDevicePathsKey = "curator_cached_device_paths";
  static const String cachedDevicePathsTimestampKey =
      "curator_cached_device_paths_timestamp";
  static const String refreshTokenKey = "curator_refresh_token";
  static const Duration cachedDevicePathsTtl = Duration(hours: 1);

  static String productName = const String.fromEnvironment(
    'PRODUCT_NAME',
    defaultValue: 'Curator',
  );

  /// To store non-critical info (like login, favorite device id, etc)
  final Map<String, dynamic> storageData;

  /// To store sensitive info about the device (like refresh token)
  final FlutterSecureStorage secureStorage;

  final Future<void> Function({required String host, int? port}) registerHostTrustedChain;

  /// The base URL for the device API
  Uri? _baseUrl;
  Api? _api;

  /// The tokens for authentication
  String? _accessToken, _refreshToken;

  /// The email identifier for the user
  String? _login;

  /// The device ID, corresponds to the certificate common name
  String? _deviceID;

  /// Seagate hardware id for Remote Access path APIs and fast reconnect.
  String? _seagateDeviceID;

  /// The status of the device to manage routing
  Status? _deviceStatus;

  /// The paths of the device to connect to
  List<DevicePath>? _devicePaths;
  DevicePaths? _cachedDevicePaths;
  DateTime? _cachedDevicePathsTimestamp;

  /// Diagnostic label for the active path (e.g. `mDNS`, `Remote Access > local`).
  String? _debugHostType;

  /// Flag to force re-detection of the device (with the Sign In screen)
  bool forceDetectFavoriteDevice = false;

  DeviceProvider(
    this.storageData,
    this.secureStorage,
    Map<String, String> secureData,
    this.registerHostTrustedChain
  ) {
    // Retrieve info from Storage...
    _login = storageData[loginKey];
    _deviceID = storageData[favoriteDeviceKey] as String?;
    final seagateRaw = storageData[seagateDeviceIDKey];
    if (seagateRaw is String) {
      _seagateDeviceID = seagateRaw;
    }
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

    final cachedPathsJson = storageData[cachedDevicePathsKey];
    if (cachedPathsJson != null && cachedPathsJson is String) {
      try {
        final decoded = jsonDecode(cachedPathsJson);
        if (decoded is Map<String, dynamic> &&
            decoded['paths'] is Map<String, dynamic>) {
          _cachedDevicePaths =
              DevicePaths.fromJson(decoded['paths'] as Map<String, dynamic>);
        } else if (decoded is List<dynamic>) {
          // Backward compatibility with paths-only cache payload.
          _cachedDevicePaths = DevicePaths(
            paths: decoded
                .map((e) => DevicePath.fromJson(e as Map<String, dynamic>))
                .toList(),
            seagateDeviceID: '',
          );
        }
      } catch (_) {
        _cachedDevicePaths = null;
      }
    }

    final cachedPathsTimestamp = storageData[cachedDevicePathsTimestampKey];
    if (cachedPathsTimestamp is int) {
      _cachedDevicePathsTimestamp =
          DateTime.fromMillisecondsSinceEpoch(cachedPathsTimestamp);
    } else if (cachedPathsTimestamp is String) {
      final parsed = int.tryParse(cachedPathsTimestamp);
      if (parsed != null) {
        _cachedDevicePathsTimestamp =
            DateTime.fromMillisecondsSinceEpoch(parsed);
      }
    }
  }

  Uri get baseUrl => _baseUrl!;
  Api get api => _api!;
  bool get deviceFound => _baseUrl != null;
  @override
  bool get isAuthenticated => _accessToken != null || _refreshToken != null;
  String get login => _login ?? '';
  @override
  String? get accessToken => _accessToken;

  /// The device ID, corresponds to the certificate common name
  String? get deviceID => _deviceID;

  /// Seagate hardware id persisted for Remote Access.
  String? get seagateDeviceID => _seagateDeviceID;

  Status? get deviceStatus => _deviceStatus;
  
  /// The device paths (local, public, relay) for connecting to the device.
  /// Available for remote devices.
  List<DevicePath>? get devicePaths => _devicePaths;
  DevicePaths? get cachedDevicePaths => _cachedDevicePaths;
  DateTime? get cachedDevicePathsTimestamp => _cachedDevicePathsTimestamp;

  String? get debugHostType => _debugHostType;

  /// Returns in-memory cached paths when present.
  DevicePaths? getCachedDevicePaths() {
    if (_cachedDevicePaths != null) {
      hcDeviceLogger.fine(
        '[Cache] Using cached device paths (${_cachedDevicePaths!.paths.length} paths)',
      );
    }
    return _cachedDevicePaths;
  }

  /// When [deviceRemoteId] is set, returns cache only if it matches that device.
  DevicePaths? getCachedDevicePathsForDevice(String deviceRemoteId) {
    final cached = getCachedDevicePaths();
    if (cached == null) return null;
    if (cached.seagateDeviceID.isEmpty) return null;
    if (cached.seagateDeviceID != deviceRemoteId) return null;
    return cached;
  }

  @Deprecated('Use getCachedDevicePathsForDevice')
  DevicePaths? getCachedDevicePathsForSeagate(String seagateDeviceID) {
    return getCachedDevicePathsForDevice(seagateDeviceID);
  }

  bool isCachedPathsExpired({
    Duration ttl = cachedDevicePathsTtl,
  }) {
    if (_cachedDevicePathsTimestamp == null) {
      return true;
    }
    return DateTime.now().difference(_cachedDevicePathsTimestamp!) > ttl;
  }

  /// Name for TTL check on cached Remote Access paths.
  bool isCacheExpired() => isCachedPathsExpired();

  /// Returns active in-memory device paths only when they belong to the
  /// provided remote device identity (if any).
  List<DevicePath>? getActiveDevicePaths({String? deviceRemoteId}) {
    if (deviceRemoteId != null && _seagateDeviceID != null && _seagateDeviceID != deviceRemoteId) {
      return null;
    }
    return _devicePaths;
  }

  void setCachedDevicePaths(
    DevicePaths paths, {
    DateTime? cachedAt,
  }) {
    _cachedDevicePaths = paths;
    _cachedDevicePathsTimestamp = cachedAt ?? DateTime.now();

    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    asyncPrefs.setString(
      cachedDevicePathsKey,
      jsonEncode(
        <String, dynamic>{
          'paths': paths.toJson(),
        },
      ),
    );
    asyncPrefs.setInt(
      cachedDevicePathsTimestampKey,
      _cachedDevicePathsTimestamp!.millisecondsSinceEpoch,
    );
  }

  void touchCachedDevicePathsTimestamp() {
    if (_cachedDevicePaths == null) {
      return;
    }
    _cachedDevicePathsTimestamp = DateTime.now();
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    asyncPrefs.setInt(
      cachedDevicePathsTimestampKey,
      _cachedDevicePathsTimestamp!.millisecondsSinceEpoch,
    );
  }

  /// Clears Remote Access path cache only.
  void clearCachedDevicePaths() {
    if (_cachedDevicePaths != null) {
      hcDeviceLogger.fine('[Cache] Device paths cache cleared');
    }
    _cachedDevicePaths = null;
    _cachedDevicePathsTimestamp = null;
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    asyncPrefs.remove(cachedDevicePathsKey);
    asyncPrefs.remove(cachedDevicePathsTimestampKey);
  }

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
  /// - [seagateDeviceID]: Hardware id from Remote Access; persisted with [deviceID].
  /// - [debugHostType]: Optional path diagnostic.
  /// - [productName]: The model name of the device.
  /// - [save]: If true (default), authentication details are saved in persistent storage.
  Future<void> setHost({
    String? host,
    int? port,
    Uri? baseUrl,
    AuthResponse? auth,
    String? login,
    Status? status,
    String? deviceID,
    String? seagateDeviceID,
    List<DevicePath>? devicePaths,
    String? debugHostType,
    String? productName,
    bool save = true,
  }) async {
    final previousDeviceId = _deviceID;
    final previousRemoteDeviceId = _seagateDeviceID;
    if (debugHostType != null) {
      _debugHostType = debugHostType;
    }
    if (baseUrl != null || host != null) {
      forceDetectFavoriteDevice = false;
      _baseUrl = baseUrl ?? createBaseUrl(host!, port);
      _api = await createApi(
        baseUrl: _baseUrl!,
        authenticator: CuratorAuthenticator(this),
        interceptors: [
          CuratorInterceptor(this),
          ...hcDeviceHttpLogInterceptors(),
        ],
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
      _seagateDeviceID = seagateDeviceID;
    }
    if (productName != null) {
      DeviceProvider.productName = productName;
    }
    if (devicePaths != null) {
      _devicePaths = devicePaths;
    } else if (deviceID != null &&
        (deviceID != previousDeviceId || seagateDeviceID != previousRemoteDeviceId)) {
      // Guard against path leakage between devices when switching host identity
      // without explicitly providing device paths for the new device.
      _devicePaths = null;
    }
    if (save) {
      _saveAuthentication(
        deviceID: deviceID,
        seagateDeviceID: seagateDeviceID,
        auth: auth,
        login: login,
        devicePaths: devicePaths,
      );
    }
    // Warning: Do not notify listeners here to avoid multiple redirects with GoRouter
  }

  void _saveAuthentication({
    String? deviceID,
    String? seagateDeviceID,
    AuthResponse? auth,
    String? login,
    List<DevicePath>? devicePaths,
  }) {
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    // Save favorite device in shared preferences
    if (deviceID != null) {
      asyncPrefs.setString(favoriteDeviceKey, deviceID);
      if (seagateDeviceID != null && seagateDeviceID.isNotEmpty) {
        asyncPrefs.setString(seagateDeviceIDKey, seagateDeviceID);
      } else {
        asyncPrefs.remove(seagateDeviceIDKey);
      }
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
  void logOut({bool notify = true}) {
    try {
      secureStorage.delete(key: refreshTokenKey);
    } catch (e) {
      hcDeviceLogger.warning('[Security] Failed to clear device refresh token', e);
    }
    try {
      if (_refreshToken != null && _api != null) {
        final AuthLogoutPost$RequestBody data = AuthLogoutPost$RequestBody(
          refreshToken: _refreshToken!,
        );
        api.authLogoutPost(body: data);
      }
    } catch (e) {
      hcDeviceLogger.warning('[Auth] Error during logout API call', e);
    }
    _accessToken = null;
    _refreshToken = null;
    clearDevice(save: true);
    if (notify) {
      notifyListeners();
    }
  }

  void clearDevice({bool save = false}) {
    if (save) {
      final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
      asyncPrefs.remove(favoriteDeviceKey);
      asyncPrefs.remove(favoriteDevicePathsKey);
      asyncPrefs.remove(seagateDeviceIDKey);
      asyncPrefs.remove(cachedDevicePathsKey);
      asyncPrefs.remove(cachedDevicePathsTimestampKey);
    }
    _baseUrl = null;
    _api = null;
    _deviceStatus = null;
    _deviceID = null;
    _seagateDeviceID = null;
    _devicePaths = null;
    _debugHostType = null;
    _cachedDevicePaths = null;
    _cachedDevicePathsTimestamp = null;
    if (save) {
      notifyListeners();
    }
  }

  void forceToReDetectDevice() => forceToRedetectDevice();

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

  Future<Api> createApi({
    required Uri baseUrl,
    Authenticator? authenticator,
    List<Interceptor>? interceptors,
  }) async {
    await registerHostTrustedChain(host: baseUrl.host, port: baseUrl.port);
    return Api.create(
      httpClient: IOClient(),
      baseUrl: baseUrl,
      authenticator: authenticator,
      interceptors: interceptors,
    );
  }
}
