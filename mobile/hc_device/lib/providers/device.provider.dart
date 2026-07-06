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

import 'dart:async' show unawaited;
import 'dart:convert' show jsonDecode, jsonEncode;
import 'package:chopper/chopper.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;
import 'package:hc_device/api/api.swagger.dart'
    show
        About,
        Api,
        AuthResponse,
        Status,
        User;
import 'package:hc_device/api/remote_access.enums.swagger.dart'
    show DevicePathType;
import 'package:hc_device/api/remote_access.swagger.dart'
    show DevicePath, DevicePaths;
import 'package:hc_device/data/api/device_api_client.dart';
import 'package:hc_device/data/repositories/auth_repository.dart';
import 'package:hc_device/data/repositories/device_repository.dart';
import 'package:hc_device/providers/auth.api.dart';
import 'package:hc_device/services/contracts/device_connectivity_sources.dart';
import 'package:hc_device/services/logger_service.dart';
import 'package:hc_device/providers/hcdevice.provider.dart';
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesAsync;

/// Backend may return duplicate entries for the same endpoint. Deduplicate by
/// address + port, preferring [DevicePathType.local] over public over remote.
List<DevicePath> dedupeDevicePathList(List<DevicePath> paths) {
  if (paths.isEmpty) {
    return paths;
  }
  int typeRank(DevicePathType t) {
    switch (t) {
      case DevicePathType.local:
        return 0;
      case DevicePathType.public:
        return 1;
      case DevicePathType.remote:
        return 2;
      case DevicePathType.swaggerGeneratedUnknown:
        return 3;
    }
  }

  String endpointKey(DevicePath p) {
    final addr = p.address.trim().toLowerCase();
    final port = p.port ?? -1;
    return '$addr\u0000$port';
  }

  final byKey = <String, DevicePath>{};
  final keyOrder = <String>[];
  var changed = false;

  for (final p in paths) {
    final key = endpointKey(p);
    final existing = byKey[key];
    if (existing == null) {
      byKey[key] = p;
      keyOrder.add(key);
      continue;
    }
    final rankP = typeRank(p.type);
    final rankExisting = typeRank(existing.type);
    if (rankP < rankExisting) {
      byKey[key] = p;
      changed = true;
    } else {
      changed = true;
    }
  }

  if (!changed && keyOrder.length == paths.length) {
    return paths;
  }

  return keyOrder.map((k) => byKey[k]!).toList(growable: false);
}

bool _sameDevicePath(DevicePath a, DevicePath b) =>
    a.address == b.address && a.port == b.port && a.type == b.type;

DevicePaths dedupeDevicePaths(DevicePaths paths) {
  final deduped = dedupeDevicePathList(paths.paths);
  if (identical(deduped, paths.paths)) {
    return paths;
  }
  if (deduped.length == paths.paths.length) {
    var allEqual = true;
    for (var i = 0; i < deduped.length; i++) {
      if (!_sameDevicePath(deduped[i], paths.paths[i])) {
        allEqual = false;
        break;
      }
    }
    if (allEqual) {
      return paths;
    }
  }
  return DevicePaths(paths: deduped, seagateDeviceID: paths.seagateDeviceID);
}

class DeviceState {
  final Uri? baseUrl;
  final Api? api;
  final String? debugHostType;
  final String? accessToken;
  final String? refreshToken;
  final String? login;
  final String? deviceID;
  final String? seagateDeviceID;
  final Status? deviceStatus;
  final List<DevicePath>? devicePaths;
  final DevicePaths? cachedDevicePaths;
  final DateTime? cachedDevicePathsTimestamp;
  final bool forceDetectFavoriteDevice;

  const DeviceState({
    this.baseUrl,
    this.api,
    this.debugHostType,
    this.accessToken,
    this.refreshToken,
    this.login,
    this.deviceID,
    this.seagateDeviceID,
    this.deviceStatus,
    this.devicePaths,
    this.cachedDevicePaths,
    this.cachedDevicePathsTimestamp,
    this.forceDetectFavoriteDevice = false,
  });

  bool get deviceFound => baseUrl != null;
  bool get isAuthenticated => accessToken != null || refreshToken != null;

  DeviceState copyWith({
    Uri? baseUrl,
    Api? api,
    String? debugHostType,
    String? accessToken,
    String? refreshToken,
    String? login,
    String? deviceID,
    String? seagateDeviceID,
    Status? deviceStatus,
    List<DevicePath>? devicePaths,
    DevicePaths? cachedDevicePaths,
    DateTime? cachedDevicePathsTimestamp,
    bool? forceDetectFavoriteDevice,
    bool clearBaseUrl = false,
    bool clearApi = false,
    bool clearAccessToken = false,
    bool clearRefreshToken = false,
    bool clearCachedDevicePaths = false,
    bool clearCachedDevicePathsTimestamp = false,
    bool clearDeviceStatus = false,
    bool clearDeviceId = false,
    bool clearSeagateDeviceId = false,
    bool clearDevicePaths = false,
    bool clearDebugHostType = false,
  }) {
    return DeviceState(
      baseUrl: clearBaseUrl ? null : (baseUrl ?? this.baseUrl),
      api: clearApi ? null : (api ?? this.api),
      debugHostType: clearDebugHostType ? null : (debugHostType ?? this.debugHostType),
      accessToken: clearAccessToken ? null : (accessToken ?? this.accessToken),
      refreshToken: clearRefreshToken ? null : (refreshToken ?? this.refreshToken),
      login: login ?? this.login,
      deviceID: clearDeviceId ? null : (deviceID ?? this.deviceID),
      seagateDeviceID:
          clearSeagateDeviceId ? null : (seagateDeviceID ?? this.seagateDeviceID),
      deviceStatus: clearDeviceStatus ? null : (deviceStatus ?? this.deviceStatus),
      devicePaths: clearDevicePaths ? null : (devicePaths ?? this.devicePaths),
      cachedDevicePaths:
          clearCachedDevicePaths ? null : (cachedDevicePaths ?? this.cachedDevicePaths),
      cachedDevicePathsTimestamp: clearCachedDevicePathsTimestamp
          ? null
          : (cachedDevicePathsTimestamp ?? this.cachedDevicePathsTimestamp),
      forceDetectFavoriteDevice:
          forceDetectFavoriteDevice ?? this.forceDetectFavoriteDevice,
    );
  }
}

class DeviceProvider extends Notifier<DeviceState>
    implements CuratorAuthProvider, DeviceConnectivitySource {
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

  late final Map<String, dynamic> _storageData;
  late final FlutterSecureStorage _secureStorage;
  late final HttpClientProvider _httpClientProvider;
  late final DeviceRepository _repo;
  late final AuthRepository _authRepo;
  final DeviceApiClientFactory _apiClientFactory = const DeviceApiClientFactory();

  @override
  DeviceState build() {
    final deps = ref.read(remoteAccessDependenciesProvider);
    _storageData = deps.storageData;
    _secureStorage = deps.secureStorage;
    _httpClientProvider = deps.httpClientProvider;
    _authRepo = AuthRepository(_secureStorage);
    _repo = DeviceRepository(() => api);

    List<DevicePath>? initialDevicePaths;
    final pathsJson = _storageData[favoriteDevicePathsKey];
    if (pathsJson is String) {
      try {
        final List<dynamic> pathsList = jsonDecode(pathsJson);
        initialDevicePaths = dedupeDevicePathList(
          pathsList
              .map((e) => DevicePath.fromJson(e as Map<String, dynamic>))
              .toList(),
        );
      } catch (_) {}
    }

    DevicePaths? initialCachedDevicePaths;
    final cachedPathsJson = _storageData[cachedDevicePathsKey];
    if (cachedPathsJson is String) {
      try {
        final decoded = jsonDecode(cachedPathsJson);
        if (decoded is Map<String, dynamic> && decoded['paths'] is Map<String, dynamic>) {
          initialCachedDevicePaths = dedupeDevicePaths(
            DevicePaths.fromJson(decoded['paths'] as Map<String, dynamic>),
          );
        }
      } catch (_) {}
    }

    DateTime? initialCachedTimestamp;
    final cachedPathsTimestamp = _storageData[cachedDevicePathsTimestampKey];
    if (cachedPathsTimestamp is int) {
      initialCachedTimestamp = DateTime.fromMillisecondsSinceEpoch(cachedPathsTimestamp);
    } else if (cachedPathsTimestamp is String) {
      final parsed = int.tryParse(cachedPathsTimestamp);
      if (parsed != null) {
        initialCachedTimestamp = DateTime.fromMillisecondsSinceEpoch(parsed);
      }
    }

    return DeviceState(
      login: _storageData[loginKey] as String?,
      deviceID: _storageData[favoriteDeviceKey] as String?,
      seagateDeviceID: _storageData[seagateDeviceIDKey] as String?,
      refreshToken: deps.secureData[refreshTokenKey],
      devicePaths: initialDevicePaths,
      cachedDevicePaths: initialCachedDevicePaths,
      cachedDevicePathsTimestamp: initialCachedTimestamp,
    );
  }

  Uri get baseUrl => state.baseUrl!;
  Api get api => state.api!;
  bool get deviceFound => state.deviceFound;
  @override
  bool get isAuthenticated => state.isAuthenticated;
  String get login => state.login ?? '';
  @override
  String? get accessToken => state.accessToken;
  String? get deviceID => state.deviceID;
  String? get seagateDeviceID => state.seagateDeviceID;
  Status? get deviceStatus => state.deviceStatus;
  List<DevicePath>? get devicePaths => state.devicePaths;
  DevicePaths? get cachedDevicePaths => state.cachedDevicePaths;
  DateTime? get cachedDevicePathsTimestamp => state.cachedDevicePathsTimestamp;
  String? get debugHostType => state.debugHostType;
  bool get forceDetectFavoriteDevice => state.forceDetectFavoriteDevice;

  /// Returns in-memory cached paths when present.
  @override
  DevicePaths? getCachedDevicePaths() {
    return state.cachedDevicePaths;
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
    if (state.cachedDevicePathsTimestamp == null) {
      return true;
    }
    return DateTime.now().difference(state.cachedDevicePathsTimestamp!) > ttl;
  }

  /// Name for TTL check on cached Remote Access paths.
  @override
  bool isCacheExpired() => isCachedPathsExpired();

  /// Returns active in-memory device paths only when they belong to the
  /// provided remote device identity (if any).
  ///
  /// Returns `null` when paths are unset or empty so callers can fall back to
  /// [getCachedDevicePathsForDevice].
  List<DevicePath>? getActiveDevicePaths({String? deviceRemoteId}) {
    if (deviceRemoteId != null &&
        state.seagateDeviceID != null &&
        state.seagateDeviceID != deviceRemoteId) {
      return null;
    }
    final paths = state.devicePaths;
    if (paths == null || paths.isEmpty) {
      return null;
    }
    return paths;
  }

  /// Active paths for [deviceRemoteId], falling back to cached Remote Access paths.
  List<DevicePath> resolveDevicePathsForDisplay({String? deviceRemoteId}) {
    final remoteId = deviceRemoteId ?? state.seagateDeviceID;
    final cached = remoteId != null && remoteId.isNotEmpty
        ? getCachedDevicePathsForDevice(remoteId)?.paths
        : getCachedDevicePaths()?.paths;
    return getActiveDevicePaths(deviceRemoteId: remoteId) ?? cached ?? const [];
  }

  @override
  void setCachedDevicePaths(
    DevicePaths paths, {
    DateTime? cachedAt,
  }) {
    final sanitized = dedupeDevicePaths(paths);
    state = state.copyWith(
      cachedDevicePaths: sanitized,
      cachedDevicePathsTimestamp: cachedAt ?? DateTime.now(),
    );

    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    asyncPrefs.setString(
      cachedDevicePathsKey,
      jsonEncode(
        <String, dynamic>{
          'paths': sanitized.toJson(),
        },
      ),
    );
    asyncPrefs.setInt(
      cachedDevicePathsTimestampKey,
      state.cachedDevicePathsTimestamp!.millisecondsSinceEpoch,
    );
  }

  @override
  void touchCachedDevicePathsTimestamp() {
    if (state.cachedDevicePaths == null) {
      return;
    }
    state = state.copyWith(cachedDevicePathsTimestamp: DateTime.now());
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    asyncPrefs.setInt(
      cachedDevicePathsTimestampKey,
      state.cachedDevicePathsTimestamp!.millisecondsSinceEpoch,
    );
  }

  /// Clears Remote Access path cache only.
  void clearCachedDevicePaths() {
    state = state.copyWith(
      clearCachedDevicePaths: true,
      clearCachedDevicePathsTimestamp: true,
    );
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
    final previousDeviceId = state.deviceID;
    final previousRemoteDeviceId = state.seagateDeviceID;
    if (baseUrl != null || host != null) {
      final resolvedBaseUrl = baseUrl ?? createBaseUrl(host!, port);
      final resolvedApi = await createApi(
        baseUrl: resolvedBaseUrl,
        authenticator: CuratorAuthenticator(this),
        interceptors: [
          CuratorInterceptor(this),
          ...hcDeviceHttpLogInterceptors(),
        ],
      );
      state = state.copyWith(
        baseUrl: resolvedBaseUrl,
        api: resolvedApi,
        forceDetectFavoriteDevice: false,
      );
    }
    state = state.copyWith(
      debugHostType: debugHostType,
      accessToken: auth?.accessToken ?? state.accessToken,
      refreshToken: auth?.refreshToken ?? state.refreshToken,
      login: login ?? state.login,
      deviceStatus: status ?? state.deviceStatus,
      deviceID: deviceID ?? state.deviceID,
      seagateDeviceID: seagateDeviceID ?? state.seagateDeviceID,
    );
    if (productName != null) {
      DeviceProvider.productName = productName;
    }
    final List<DevicePath>? pathsForState = devicePaths != null
        ? dedupeDevicePathList(devicePaths)
        : null;
    if (pathsForState != null) {
      state = state.copyWith(devicePaths: pathsForState);
    } else if (deviceID != null &&
        (deviceID != previousDeviceId || seagateDeviceID != previousRemoteDeviceId)) {
      state = state.copyWith(devicePaths: const <DevicePath>[]);
    }
    if (save) {
      unawaited(_saveAuthentication(
        deviceID: deviceID,
        seagateDeviceID: seagateDeviceID,
        auth: auth,
        login: login,
        devicePaths: pathsForState,
      ));
    }
  }

  Future<void> _saveAuthentication({
    String? deviceID,
    String? seagateDeviceID,
    AuthResponse? auth,
    String? login,
    List<DevicePath>? devicePaths,
  }) async {
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    // Save favorite device in shared preferences
    if (deviceID != null) {
      await asyncPrefs.setString(favoriteDeviceKey, deviceID);
      if (seagateDeviceID != null && seagateDeviceID.isNotEmpty) {
        await asyncPrefs.setString(seagateDeviceIDKey, seagateDeviceID);
      } else {
        await asyncPrefs.remove(seagateDeviceIDKey);
      }
    }
    // Save/Clear device paths in shared preferences
    if (devicePaths != null) {
      if (devicePaths.isNotEmpty) {
        try {
          final pathsJson = jsonEncode(
            devicePaths.map((path) => path.toJson()).toList(),
          );
          await asyncPrefs.setString(favoriteDevicePathsKey, pathsJson);
        } catch (_) {}
      } else {
        await asyncPrefs.remove(favoriteDevicePathsKey);
      }
    }
    // Save refresh token in secure storage
    final refreshToken = auth?.refreshToken;
    if (refreshToken != null) {
      await _authRepo.writeSecureString(refreshTokenKey, refreshToken);
    }
    // Save login in shared preferences
    if (login != null) {
      await asyncPrefs.setString(loginKey, login);
    }
  }

  @override
  bool isRefreshRequest(Request? request) {
    return request?.url.path.contains('/auth/refresh') ?? false;
  }

  @override
  bool shouldLogoutOnRefreshFailure(Object error) => false;

  void setDeviceStatus(Status status) => state = state.copyWith(deviceStatus: status);

  @override
  Future<String> refreshAccessToken() async {
    try {
      final refreshToken = state.refreshToken;
      if (refreshToken == null || refreshToken.isEmpty) {
        throw StateError('Refresh token is missing');
      }
      final response = await _repo.refreshToken(refreshToken: refreshToken);
      if (response.isSuccessful) {
        _applyAuthenticatedState(
          accessToken: response.body?.accessToken,
          refreshToken: response.body?.refreshToken,
        );
        unawaited(_saveAuthentication(auth: response.body));
        return state.accessToken ?? '';
      } else {
        throw response.error ?? 'Refresh token error';
      }
    } catch (e) {
      rethrow;
    }
  }

  @override
  Future<void> logOut({bool notify = true}) async {
    await _authRepo.deleteSecureString(refreshTokenKey);
    try {
      final token = state.refreshToken;
      if (token != null && token.isNotEmpty && state.api != null) {
        await _repo.logout(refreshToken: token);
      }
    } catch (e) {
      hcDeviceLogger.warning('[Auth] Error during logout API call', e);
    }
    _clearAuthState();
    clearDevice(save: true);
  }

  void _applyAuthenticatedState({
    required String? accessToken,
    required String? refreshToken,
  }) {
    state = state.copyWith(
      accessToken: accessToken,
      refreshToken: refreshToken,
    );
  }

  void _clearAuthState() {
    state = state.copyWith(clearAccessToken: true, clearRefreshToken: true);
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
    state = state.copyWith(
      clearBaseUrl: true,
      clearApi: true,
      clearDeviceStatus: true,
      clearDeviceId: true,
      clearSeagateDeviceId: true,
      clearDevicePaths: true,
      clearDebugHostType: true,
      clearCachedDevicePaths: true,
      clearCachedDevicePathsTimestamp: true,
    );
  }

  void forceToReDetectDevice() => forceToRedetectDevice();

  void forceToRedetectDevice() {
    clearDevice();
    state = state.copyWith(forceDetectFavoriteDevice: true);
  }

  static Uri createBaseUrl(String host, int? port) {
    host = host.trim();

    // Defensive normalization for Remote Access payloads that may incorrectly
    // include a full URL in the "address" field instead of host-only value.
    final uriLikeHost = host.startsWith(RegExp(r'https?://', caseSensitive: false))
        ? host
        : 'https://$host';
    final parsed = Uri.tryParse(uriLikeHost);
    if (parsed != null && parsed.host.isNotEmpty) {
      host = parsed.host;
      port ??= parsed.hasPort ? parsed.port : null;
    }

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
    return _apiClientFactory.create(
      baseUrl: baseUrl,
      authProvider: this,
      httpClient: _httpClientProvider(),
      authenticator: authenticator,
      interceptors: interceptors,
    );
  }

  Future<Response<AuthResponse>> signInWithPassword({
    required String email,
    required String password,
  }) {
    return _repo.loginWithPassword(email: email, password: password);
  }

  Future<Response> sendResetPasswordEmail({required String email}) {
    return _repo.sendResetPasswordEmail(email: email);
  }

  Future<Response<Status>> fetchStatus() {
    return _repo.getStatus();
  }

  Future<Response<About>> fetchAbout() {
    return _repo.getAbout();
  }

  Future<Response<User>> fetchCurrentUser() {
    return _repo.getCurrentUser();
  }
}
