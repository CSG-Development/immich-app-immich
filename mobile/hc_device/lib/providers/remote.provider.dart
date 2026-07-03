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

import 'dart:async' show Completer, unawaited;
import 'dart:io' show HttpClient, SecurityContext, X509Certificate;
import 'package:http/io_client.dart' show IOClient;

import 'package:basic_utils/basic_utils.dart' show StringUtils;
import 'package:chopper/chopper.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;
import 'package:hc_device/data/api/remote_api_client.dart';
import 'package:hc_device/data/errors/domain_errors.dart';
import 'package:hc_device/data/repositories/auth_repository.dart';
import 'package:hc_device/data/repositories/remote_repository.dart';
import 'package:hc_device/api/remote_access.swagger.dart'
    show Device, DevicePaths, InitiateResponse$Response, RemoteAccess, TokenResponse$Response;
import 'package:hc_device/providers/auth.api.dart';
import 'package:hc_device/providers/hcdevice.provider.dart';
import 'package:hc_device/services/auth/refresh_failure_classifier.dart';
import 'package:hc_device/services/contracts/device_connectivity_sources.dart';
import 'package:hc_device/services/logger_service.dart';
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesAsync;

RemoteCodeFailureType mapRemoteCodeFailureType(
  int? statusCode, {
  String? message,
}) {
  final normalizedMessage = (message ?? '').toLowerCase();
  switch (statusCode) {
    case 401:
      return RemoteCodeFailureType.invalidCode;
    case 403:
      // Some environments return 403 for an incorrect remote code.
      // Preserve explicit authorization failures and classify all other
      // validation rejections as invalid code for correct UI messaging.
      if (normalizedMessage.contains('not allowed') ||
          normalizedMessage.contains('email') && normalizedMessage.contains('allowed')) {
        return RemoteCodeFailureType.unauthorized;
      }
      return RemoteCodeFailureType.invalidCode;
    case 410:
      return RemoteCodeFailureType.expiredCode;
    case 400:
    case 422:
      return RemoteCodeFailureType.invalidCode;
    default:
      return RemoteCodeFailureType.unknown;
  }
}

class RemoteState {
  final String? accessToken;
  final String? refreshToken;
  final String? reference;
  const RemoteState({this.accessToken, this.refreshToken, this.reference});
  bool get isAuthenticated => accessToken != null || refreshToken != null;
  RemoteState copyWith({
    String? accessToken,
    String? refreshToken,
    String? reference,
    bool clearReference = false,
    bool clearAccessToken = false,
    bool clearRefreshToken = false,
  }) {
    return RemoteState(
      accessToken: clearAccessToken ? null : (accessToken ?? this.accessToken),
      refreshToken: clearRefreshToken ? null : (refreshToken ?? this.refreshToken),
      reference: clearReference ? null : (reference ?? this.reference),
    );
  }
}

class RemoteProvider extends Notifier<RemoteState>
    implements CuratorAuthProvider, RemoteConnectivitySource {
  /// TODO: Replace with the production URL then remove HttpClient override
  static const String baseUrl =
      'https://hc-remote-access-env-https.eba-a2nvhpbm.us-west-2.elasticbeanstalk.com:443/api';
  static const String refreshKey = 'curator_remote_refresh_token';
  static const String clientIdKey = 'curator_remote_client_id';
  static const String referenceKey = 'curator_remote_reference';
  static const String currentSessionIdKey = 'remote_current_session_id';
  static const String lastProactiveRefreshSessionIdKey =
      'remote_last_proactive_refresh_session_id';
  static const String accessExpiryEpochMsKey = 'remote_access_expiry_epoch_ms';
  static const Duration refreshExpirySafetySkew = Duration(seconds: 90);

  late String _clientId;
  late RemoteAccess _api;
  late final RemoteRepository _repo;
  late final AuthRepository _authRepo;
  final RemoteApiClientFactory _apiClientFactory = const RemoteApiClientFactory();

  late final Map<String, dynamic> _storageData;
  late final FlutterSecureStorage _secureStorage;
  late final String? _currentSessionId;
  late final String? _lastProactiveRefreshSessionId;
  late final DateTime? _accessExpiryAt;
  late final bool _isMainRuntime;
  Completer<String>? _refreshCompleter;

  /// Determines whether a refresh failure is a hard authentication error
  /// (token expired/revoked) versus a transient failure (network, timeout, 5xx).
  /// Only hard auth errors should trigger logout.
  @override
  bool shouldLogoutOnRefreshFailure(Object error) =>
      RefreshFailureClassifier.shouldLogoutOnRefreshFailure(error);

  bool _shouldLogoutAfterRefreshFailure(Object error) {
    return shouldLogoutOnRefreshFailure(error);
  }

  @override
  RemoteState build() {
    final deps = ref.read(remoteAccessDependenciesProvider);
    _storageData = deps.storageData;
    _secureStorage = deps.secureStorage;
    _isMainRuntime = deps.isMainRuntime;
    _authRepo = AuthRepository(_secureStorage);
    final secureData = deps.secureData;
    _currentSessionId = _readStorageString(currentSessionIdKey);
    _lastProactiveRefreshSessionId = _readStorageString(
      lastProactiveRefreshSessionIdKey,
    );
    _accessExpiryAt = _readStorageDateTimeFromEpoch(accessExpiryEpochMsKey);
    _initClientId();

    // TODO(security): Remove this override and restore proper TLS certificate
    // validation for remote access requests.
    final HttpClient client = HttpClient(context: SecurityContext.defaultContext)
      ..badCertificateCallback = (
        X509Certificate cert,
        String host,
        int port,
      ) {
        return true;
      };

    _api = _apiClientFactory.create(
      baseUrl: Uri.parse(baseUrl),
      authProvider: this,
      httpClient: IOClient(client),
    );
    _repo = RemoteRepository(() => _api);
    final initial = RemoteState(
      refreshToken: secureData[refreshKey],
      reference: secureData[referenceKey],
    );
    if (initial.isAuthenticated) {
      logger.debug(
        '[Provider] Remote provider initialized with existing auth data '
        'mainRuntime=$_isMainRuntime sessionId=${_currentSessionId ?? '-'}',
      );
      if (_shouldSkipProactiveRefresh()) {
        logger.info(
          '[Provider] Proactive remote refresh skipped on initialization '
          'mainRuntime=$_isMainRuntime sessionId=${_currentSessionId ?? '-'}',
        );
      } else {
        unawaited(
          Future<void>(() async {
            try {
              await refreshAccessToken();
              await _markProactiveRefreshDoneForCurrentSession();
            } catch (e) {
              final failure = RefreshFailureClassifier.describe(e);
              final shouldLogout = _shouldLogoutAfterRefreshFailure(e);
              logger.error(
                '[Provider] Failed to refresh remote access token on initialization '
                'mainRuntime=$_isMainRuntime shouldLogout=$shouldLogout ${failure.logSuffix}',
                e,
              );
              if (shouldLogout) {
                await logOut();
              }
            }
          }),
        );
      }
    } else {
      logger.debug('[Provider] Remote provider initialized without auth data');
    }
    return initial;
  }

  @override
  String? get accessToken => state.accessToken;
  String? get refreshToken => state.refreshToken;
  String get clientId => _clientId;
  @override
  bool get isAuthenticated => state.isAuthenticated;
  String? get reference => state.reference;
  RemoteAccess get api => _api;

  Future<RemoteAccess> getPinnedApi() async => _api;

  /// Initialize clientId with a unique, persistent identifier per device/app install
  void _initClientId() {
    String? value = _storageData[clientIdKey];
    if (value != null) {
      _clientId = value;
    } else {
      _clientId = StringUtils.generateRandomString(
        42,
        alphabet: true,
        numeric: true,
        special: false,
        uppercase: false,
        lowercase: true,
      );
      final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
      asyncPrefs.setString(clientIdKey, _clientId);
    }
  }

  Future<void> setReference(String? ref) async {
    state = state.copyWith(reference: ref);
    if (state.reference != null) {
      await _authRepo.writeSecureString(referenceKey, state.reference!);
    }
  }

  Future<void> setAuthToken({
    required TokenResponse$Response auth,
    bool notify = true,
  }) async {
    _applyAuthenticatedState(
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
    );
    await _saveRefreshToken(refreshToken: auth.refreshToken);
    await _saveAccessExpiry(expiresInSeconds: auth.expiresIn);
    await _authRepo.deleteSecureString(referenceKey);
  }

  bool _shouldSkipProactiveRefresh() {
    if (!_isMainRuntime) {
      return true;
    }

    final expiry = _accessExpiryAt;
    if (expiry != null) {
      final threshold = DateTime.now().add(refreshExpirySafetySkew);
      if (expiry.isAfter(threshold)) {
        logger.info(
          '[Provider] Proactive remote refresh skipped: access token still fresh',
        );
        return true;
      }
    }

    final currentSessionId = _currentSessionId;
    if (currentSessionId != null &&
        currentSessionId.isNotEmpty &&
        currentSessionId == _lastProactiveRefreshSessionId) {
      logger.info(
        '[Provider] Proactive remote refresh skipped: already refreshed this session',
      );
      return true;
    }
    return false;
  }

  void _applyAuthenticatedState({
    required String? accessToken,
    required String? refreshToken,
  }) {
    state = state.copyWith(
      accessToken: accessToken,
      refreshToken: refreshToken,
      clearReference: true,
    );
  }

  void _clearAuthState() {
    state = state.copyWith(
      clearAccessToken: true,
      clearRefreshToken: true,
      clearReference: true,
    );
  }

  @override
  bool isRefreshRequest(Request? request) {
    return request?.url.path.contains('/auth/refresh') ?? false;
  }

  @override
  Future<String> refreshAccessToken() async {
    if (_refreshCompleter != null && !_refreshCompleter!.isCompleted) {
      return _refreshCompleter!.future;
    }
    _refreshCompleter = Completer<String>();
    try {
      final refreshToken = state.refreshToken;
      if (refreshToken == null || refreshToken.isEmpty) {
        final failure = RefreshFailureClassifier.describe(
          StateError('Refresh token is missing'),
        );
        logger.warning(
          '[Auth/Refresh] failed mainRuntime=$_isMainRuntime ${failure.logSuffix}',
        );
        throw StateError('Refresh token is missing');
      }
      final response = await _repo.refreshToken(
        clientId: _clientId,
        refreshToken: refreshToken,
      );
      if (response.isSuccessful) {
        final TokenResponse$Response data = response.body!;
        await setAuthToken(auth: data, notify: false);
        final accessToken = state.accessToken ?? '';
        _refreshCompleter!.complete(accessToken);
        return accessToken;
      }
      final failure = RefreshFailureClassifier.describe(response);
      logger.warning(
        '[Auth/Refresh] failed mainRuntime=$_isMainRuntime ${failure.logSuffix}',
      );
      throw response;
    } catch (e) {
      if (e is! Response && e is! StateError) {
        final failure = RefreshFailureClassifier.describe(e);
        logger.warning(
          '[Auth/Refresh] failed mainRuntime=$_isMainRuntime ${failure.logSuffix}',
          e,
        );
      }
      if (!_refreshCompleter!.isCompleted) {
        _refreshCompleter!.completeError(e);
      }
      rethrow;
    } finally {
      _refreshCompleter = null;
    }
  }

  /// Save or delete the refresh token in secure storage
  Future<void> _saveRefreshToken({String? refreshToken}) async {
    if (refreshToken != null) {
      await _authRepo.writeSecureString(refreshKey, refreshToken);
    } else {
      await _authRepo.deleteSecureString(refreshKey);
    }
  }

  Future<void> _saveAccessExpiry({required int expiresInSeconds}) async {
    final expiryEpochMs =
        DateTime.now().add(Duration(seconds: expiresInSeconds)).millisecondsSinceEpoch;
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setInt(accessExpiryEpochMsKey, expiryEpochMs);
  }

  Future<void> _markProactiveRefreshDoneForCurrentSession() async {
    final currentSessionId = _currentSessionId;
    if (currentSessionId == null || currentSessionId.isEmpty) {
      return;
    }
    final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
    await asyncPrefs.setString(
      lastProactiveRefreshSessionIdKey,
      currentSessionId,
    );
  }

  @override
  Future<void> logOut({bool notify = true}) async {
    _clearAuthState();
    if (_isMainRuntime) {
      await _authRepo.deleteSecureString(refreshKey);
      await _authRepo.deleteSecureString(referenceKey);
      final SharedPreferencesAsync asyncPrefs = SharedPreferencesAsync();
      await asyncPrefs.remove(accessExpiryEpochMsKey);
      logger.debug('[Provider] Remote logged out');
    } else {
      logger.info('[Provider] Remote logout skipped secure storage clear (non-main runtime)');
    }
  }

  /// Backward-compatible alias.
  void logout() {
    unawaited(logOut());
  }

  Future<Response<InitiateResponse$Response>> initiateEmailAccess({
    required String email,
    required String clientFriendlyName,
  }) {
    return _repo.initiateEmailAccess(
      email: email,
      clientId: _clientId,
      clientFriendlyName: clientFriendlyName,
    );
  }

  Future<Response<TokenResponse$Response>> validateEmailCode({
    required String code,
    required String reference,
  }) {
    return _repo.validateEmailCode(
      code: code,
      clientId: _clientId,
      reference: reference,
    );
  }

  @override
  Future<Response<List<Device>>> fetchDevices() => _repo.getDevices();

  @override
  Future<Response<DevicePaths>> fetchDevicePaths({required String deviceID}) {
    return _repo.getDevicePaths(deviceID: deviceID);
  }

  RemoteCodeValidationError classifyCodeFailure(Response<dynamic> response) {
    final status = response.statusCode;
    final message = (response.error ?? '').toString();
    return RemoteCodeValidationError(
      mapRemoteCodeFailureType(status, message: message),
      message,
    );
  }

  String? _readStorageString(String key) {
    final value = _storageData[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    return null;
  }

  DateTime? _readStorageDateTimeFromEpoch(String key) {
    final value = _storageData[key];
    if (value is int) {
      return DateTime.fromMillisecondsSinceEpoch(value);
    }
    if (value is String) {
      final parsed = int.tryParse(value);
      if (parsed != null) {
        return DateTime.fromMillisecondsSinceEpoch(parsed);
      }
    }
    return null;
  }
}
