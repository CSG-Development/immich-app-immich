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
import 'dart:io' show HttpClient, SecurityContext;
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
import 'package:hc_device/services/contracts/device_connectivity_sources.dart';
import 'package:hc_device/services/logger_service.dart';
import 'package:shared_preferences/shared_preferences.dart'
    show SharedPreferencesAsync;

RemoteCodeFailureType mapRemoteCodeFailureType(int? statusCode) {
  switch (statusCode) {
    case 401:
    case 403:
      return RemoteCodeFailureType.unauthorized;
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

  late String _clientId;
  late RemoteAccess _api;
  late final RemoteRepository _repo;
  late final AuthRepository _authRepo;
  final RemoteApiClientFactory _apiClientFactory = const RemoteApiClientFactory();

  late final Map<String, dynamic> _storageData;
  late final FlutterSecureStorage _secureStorage;
  late final Future<void> Function({required String host, int? port})
      _registerHostTrustedChain;

  bool _shouldLogoutAfterRefreshFailure(Object error) {
    final message = error.toString().toLowerCase();
    return message.contains('401') ||
        message.contains('403') ||
        message.contains('unauthorized') ||
        message.contains('forbidden') ||
        (message.contains('refresh') && message.contains('invalid'));
  }

  @override
  RemoteState build() {
    final deps = ref.read(remoteAccessDependenciesProvider);
    _storageData = deps.storageData;
    _secureStorage = deps.secureStorage;
    _registerHostTrustedChain = deps.registerHostTrustedChain;
    _authRepo = AuthRepository(_secureStorage);
    final secureData = deps.secureData;
    _initClientId();

    final HttpClient client = HttpClient(context: SecurityContext.defaultContext);

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
        '[Provider] Remote provider initialized with existing auth data',
      );
      // Delay refresh to the next microtask so this notifier state is fully initialized.
      unawaited(
        Future<void>(() async {
          try {
            await refreshAccessToken();
          } catch (e) {
            final shouldLogout = _shouldLogoutAfterRefreshFailure(e);
            logger.error(
              '[Provider] Failed to refresh remote access token on initialization',
              e,
            );
            // Keep existing refresh token on transient network failures
            // (airplane mode/offline), so reconnect flows don't immediately
            // fall into OTP due to forced logout.
            if (shouldLogout) {
              await logOut();
            }
          }
        }),
      );
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

  Future<RemoteAccess> getPinnedApi() async {
    final uri = Uri.parse(baseUrl);
    await _registerHostTrustedChain(host: uri.host, port: uri.port);
    return _api;
  }

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
    state = state.copyWith(
      accessToken: auth.accessToken,
      refreshToken: auth.refreshToken,
      clearReference: true,
    );
    await _saveRefreshToken(refreshToken: auth.refreshToken);
    await _authRepo.deleteSecureString(referenceKey);
  }

  @override
  bool isRefreshRequest(Request? request) {
    return request?.url.path.contains('/auth/refresh') ?? false;
  }

  @override
  Future<String> refreshAccessToken() async {
    try {
      final refreshToken = state.refreshToken;
      if (refreshToken == null || refreshToken.isEmpty) {
        throw StateError('Refresh token is missing');
      }
      final response = await _repo.refreshToken(
        clientId: _clientId,
        refreshToken: refreshToken,
      );
      if (response.isSuccessful) {
        final TokenResponse$Response data = response.body!;
        await setAuthToken(auth: data, notify: false);
        return state.accessToken ?? '';
      } else {
        throw response.error ?? 'Refresh token error';
      }
    } catch (e) {
      rethrow;
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

  @override
  Future<void> logOut({bool notify = true}) async {
    state = state.copyWith(
      clearAccessToken: true,
      clearRefreshToken: true,
      clearReference: true,
    );
    await _authRepo.deleteSecureString(refreshKey);
    await _authRepo.deleteSecureString(referenceKey);
    logger.debug('[Provider] Remote logged out');
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
    return RemoteCodeValidationError(mapRemoteCodeFailureType(status), message);
  }
}
