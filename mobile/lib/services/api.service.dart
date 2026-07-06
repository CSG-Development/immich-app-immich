import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cupertino_http/cupertino_http.dart' show NSErrorClientException;
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:http/http.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/network.repository.dart';
import 'package:immich_mobile/models/connection_state.model.dart';
import 'package:immich_mobile/models/auth/auxilary_endpoint.model.dart';
import 'package:immich_mobile/services/firebase_performance_wrapper.dart';
import 'package:immich_mobile/utils/certificates_pinning/http_cert_pinning_manager.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

class ConnectionRecoveryInterceptor extends BaseClient {
  final Client _inner;
  final Function(String) _onConnectionError;
  final Function(String)? _onRequestSuccess;
  final void Function(String, Duration, bool isHard)? _onSlowRequest;

  ConnectionRecoveryInterceptor(
    this._inner,
    this._onConnectionError, {
    Function(String)? onRequestSuccess,
    void Function(String, Duration, bool isHard)? onSlowRequest,
  }) : _onRequestSuccess = onRequestSuccess,
       _onSlowRequest = onSlowRequest;

  static const Duration _slowRequestSoftThreshold = Duration(seconds: 8);
  static const Duration _slowRequestHardThreshold = Duration(seconds: 15);

  static const String _nsUrlErrorDomain = 'NSURLErrorDomain';

  static const Set<int> _nsUrlTransportErrorCodes = {
    -1001,
    -1003,
    -1004,
    -1005,
    -1006,
    -1009,
    -1020,
  };

  static final RegExp _nsUrlErrorPattern = RegExp(r'\[domain=([^,\]]+), code=(-?\d+)\]');

  bool _isConnectionError(dynamic error) => isTransportFailure(error);

  static bool isTransportFailure(Object error) {
    if (error is SocketException ||
        error is TimeoutException ||
        error is TlsException ||
        error is HandshakeException ||
        error is HttpException) {
      return true;
    }
    if (error is NSErrorClientException) {
      return _isNsUrlTransportFailure(error);
    }
    if (error is ClientException) {
      return _isClientTransportFailure(error);
    }
    return false;
  }

  static bool _isNsUrlTransportFailure(NSErrorClientException error) {
    final parsed = _parseNsUrlError(error.toString());
    return parsed != null && _isNsUrlTransportCode(parsed.$1, parsed.$2);
  }

  static bool _isNsUrlTransportCode(String domain, int code) {
    if (domain != _nsUrlErrorDomain || code == -999) {
      return false;
    }
    return _nsUrlTransportErrorCodes.contains(code);
  }

  static bool _isClientTransportFailure(ClientException error) {
    final fromMessage = _parseNsUrlError(error.message);
    if (fromMessage != null) {
      return _isNsUrlTransportCode(fromMessage.$1, fromMessage.$2);
    }
    final fromDescription = _parseNsUrlError(error.toString());
    if (fromDescription != null) {
      return _isNsUrlTransportCode(fromDescription.$1, fromDescription.$2);
    }
    return false;
  }

  static (String, int)? _parseNsUrlError(String text) {
    final match = _nsUrlErrorPattern.firstMatch(text);
    if (match == null) {
      return null;
    }
    final code = int.tryParse(match.group(2)!);
    if (code == null) {
      return null;
    }
    return (match.group(1)!, code);
  }

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final startedAt = DateTime.now();
    var softReported = false;
    var hardReported = false;
    final softTimer = Timer(_slowRequestSoftThreshold, () {
      softReported = true;
      _onSlowRequest?.call(request.url.toString(), _slowRequestSoftThreshold, false);
    });
    final hardTimer = Timer(_slowRequestHardThreshold, () {
      hardReported = true;
      _onSlowRequest?.call(request.url.toString(), _slowRequestHardThreshold, true);
    });

    try {
      final response = await _inner.send(request);
      _onRequestSuccess?.call(request.url.toString());
      return response;
    } catch (e) {
      if (_isConnectionError(e)) {
        _onConnectionError(request.url.toString());
      }
      rethrow;
    } finally {
      softTimer.cancel();
      hardTimer.cancel();
      final elapsed = DateTime.now().difference(startedAt);
      if (!softReported && elapsed >= _slowRequestSoftThreshold) {
        _onSlowRequest?.call(request.url.toString(), elapsed, false);
      }
      if (!hardReported && elapsed >= _slowRequestHardThreshold) {
        _onSlowRequest?.call(request.url.toString(), elapsed, true);
      }
    }
  }

  @override
  void close() {
    // Do not close the shared underlying client from interceptor wrappers.
    super.close();
  }
}

class PerformanceHttpClient extends BaseClient {
  final Client _inner;
  final _log = Logger("PerformanceHttpClient");

  PerformanceHttpClient(this._inner);

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    final trace = FirebasePerformanceWrapper.newHttpMetric(
      request.url.toString(),
      HttpMethod.values.firstWhere(
        (method) => method.toString().split('.').last.toUpperCase() == request.method,
        orElse: () => HttpMethod.Get,
      ),
    );

    // Use no-op trace if Firebase is not available
    final httpMetric = trace ?? NoOpHttpMetric();
    await httpMetric.start();

    try {
      final response = await _inner.send(request);
      httpMetric.httpResponseCode = response.statusCode;
      httpMetric.responseContentType = response.headers['content-type'];
      httpMetric.responsePayloadSize = int.tryParse(response.headers['content-length'] ?? '0');
      await httpMetric.stop();
      return response;
    } on TlsException catch (e) {
      await httpMetric.stop();
      _log.warning('[HTTP] TLS failure ${request.method} ${request.url}', e);
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'TLS/SSL communication failed: ${request.method} ${request.url}',
        e,
        StackTrace.current,
      );
    } on SocketException catch (e) {
      await httpMetric.stop();
      _log.warning('[HTTP] Socket failure ${request.method} ${request.url}', e);
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'Socket operation failed: ${request.method} ${request.url}',
        e,
        StackTrace.current,
      );
    } on ClientException catch (e) {
      await httpMetric.stop();
      if (ConnectionRecoveryInterceptor.isTransportFailure(e)) {
        rethrow;
      }
      _log.warning('[HTTP] Unhandled transport failure ${request.method} ${request.url}', e);
      rethrow;
    } catch (e) {
      await httpMetric.stop();
      _log.warning('[HTTP] Unhandled transport failure ${request.method} ${request.url}', e);
      rethrow;
    }
  }
}

class ApiService implements Authentication {
  late ApiClient _apiClient;
  late PerformanceHttpClient _httpClient;
  late ConnectionRecoveryInterceptor _connectionRecoveryInterceptor;
  late Client _baseClient;
  bool _httpClientInitialized = false;

  late UsersApi usersApi;
  late AuthenticationApi authenticationApi;
  late AuthenticationApi oAuthApi;
  late AlbumsApi albumsApi;
  late AssetsApi assetsApi;
  late SearchApi searchApi;
  late ServerApi serverInfoApi;
  late MapApi mapApi;
  late PartnersApi partnersApi;
  late PeopleApi peopleApi;
  late SharedLinksApi sharedLinksApi;
  late SyncApi syncApi;
  late SystemConfigApi systemConfigApi;
  late ActivitiesApi activitiesApi;
  late DownloadApi downloadApi;
  late TrashApi trashApi;
  late StacksApi stacksApi;
  late ViewsApi viewApi;
  late MemoriesApi memoriesApi;
  late SessionsApi sessionsApi;
  late TagsApi tagsApi;

  final _log = Logger("ApiService");
  final StreamController<ConnectionState> _connectionStateController = StreamController<ConnectionState>.broadcast();
  Stream<ConnectionState> get connectionStateChanges => _connectionStateController.stream;
  ConnectionStatus _lastConnectionStatus = ConnectionStatus.connected;

  static const Duration _endpointAvailabilityPingTimeout = Duration(seconds: 15);
  static const Duration endpointSwitchSettleTimeout = Duration(seconds: 15);
  static const Duration endpointSwitchPollInterval = Duration(milliseconds: 200);

  bool _isSetEndpoint = false;
  Future<void> _endpointSwitchQueue = Future<void>.value();

  bool get isEndpointSwitchInProgress => _isSetEndpoint;

  Future<void> waitForEndpointSwitchToSettle() async {
    final deadline = DateTime.now().add(endpointSwitchSettleTimeout);
    while (DateTime.now().isBefore(deadline)) {
      if (!isEndpointSwitchInProgress) {
        return;
      }
      await Future<void>.delayed(endpointSwitchPollInterval);
    }
    _log.warning('[auth-path] endpoint switch settle wait timed out');
  }

  /// Optional hook (set from main tab shell): run Curator device re-detection after
  /// [ConnectionStatus.reconnecting] is published.
  void Function()? curatorNetworkForceReconnectHandler;
  void Function(String, Duration, bool isHard)? curatorNetworkSlowRequestHandler;

  ApiService() {
    _initHttpClient();
    // Initialize with empty endpoint first, then restore the last known endpoint (if any).
    setEndpoint('');
    final endpoint = Store.tryGet(StoreKey.serverEndpoint);
    if (endpoint != null && endpoint.isNotEmpty) {
      setEndpoint(endpoint);
    }
  }

  static Future<ApiService> instantiate() async {
    await HttpCertPinningManager.ensureInitialized();
    return ApiService();
  }

  void _syncHttpClientFromRepository() {
    _baseClient = NetworkRepository.client;
    _connectionRecoveryInterceptor = ConnectionRecoveryInterceptor(
      _baseClient,
      _handleConnectionError,
      onRequestSuccess: _handleRequestSuccess,
      onSlowRequest: _handleSlowRequest,
    );
    _httpClient = PerformanceHttpClient(_connectionRecoveryInterceptor);
  }

  void _initHttpClient() {
    if (_httpClientInitialized) {
      return;
    }

    _syncHttpClientFromRepository();
    _httpClientInitialized = true;
  }

  String? _accessToken;

  Future<void> _handleConnectionError(String failedUrl) async {
    dPrint(() => '_handleConnectionError: Connection error detected for $failedUrl');

    // Do not notify connection state while endpoint switching is in progress
    if (_isSetEndpoint) {
      dPrint(() => '_handleConnectionError: Skipping notification - endpoint switching in progress');
      return;
    }

    // Ignore errors from requests that targeted an endpoint that is no longer active
    final activeEndpoint = Store.tryGet(StoreKey.serverEndpoint);
    if (activeEndpoint != null && activeEndpoint.isNotEmpty && !failedUrl.startsWith(activeEndpoint)) {
      dPrint(
        () =>
            '_handleConnectionError: Skipping notification - failed URL does not match active endpoint $activeEndpoint',
      );
      return;
    }

    final isAuthenticated = Store.tryGet(StoreKey.currentUser) != null;
    if (!isAuthenticated) {
      dPrint(() => '_handleConnectionError: Skipping notification - not authenticated');
      return;
    }

    notifyConnectionState(
      ConnectionState(
        status: ConnectionStatus.reconnecting,
        lastErrorUrl: failedUrl,
        lastErrorTime: DateTime.now(),
        connectionType: ConnectionType.api,
      ),
    );

    try {
      curatorNetworkForceReconnectHandler?.call();
    } catch (error, stackTrace) {
      _log.warning('curatorNetworkForceReconnectHandler failed', error, stackTrace);
    }
  }

  void _handleRequestSuccess(String requestUrl) {
    if (_lastConnectionStatus == ConnectionStatus.connected) {
      return;
    }

    final activeEndpoint = Store.tryGet(StoreKey.serverEndpoint);
    if (activeEndpoint != null && activeEndpoint.isNotEmpty && !requestUrl.startsWith(activeEndpoint)) {
      return;
    }

    final isAuthenticated = Store.tryGet(StoreKey.currentUser) != null;
    if (!isAuthenticated) {
      return;
    }

    _log.info('Publishing connected state after successful request: $requestUrl');
    notifyConnectionState(
      const ConnectionState(status: ConnectionStatus.connected, connectionType: ConnectionType.api),
    );
  }

  void _handleSlowRequest(String requestUrl, Duration elapsed, bool isHard) {
    try {
      curatorNetworkSlowRequestHandler?.call(requestUrl, elapsed, isHard);
    } catch (error, stackTrace) {
      _log.warning('curatorNetworkSlowRequestHandler failed', error, stackTrace);
    }
  }

  void notifyConnectionState(ConnectionState state) {
    try {
      _lastConnectionStatus = state.status;
      if (!_connectionStateController.isClosed) {
        _connectionStateController.add(state);
      }
    } catch (error, stackTrace) {
      _log.warning("Failed to notify connection state (non-critical)", error, stackTrace);
    }
  }

  void setEndpoint(String endpoint) {
    _initHttpClient();

    _apiClient = ApiClient(basePath: endpoint, authentication: this);
    _apiClient.client = _httpClient;
    usersApi = UsersApi(_apiClient);
    authenticationApi = AuthenticationApi(_apiClient);
    oAuthApi = AuthenticationApi(_apiClient);
    albumsApi = AlbumsApi(_apiClient);
    assetsApi = AssetsApi(_apiClient);
    serverInfoApi = ServerApi(_apiClient);
    searchApi = SearchApi(_apiClient);
    mapApi = MapApi(_apiClient);
    partnersApi = PartnersApi(_apiClient);
    peopleApi = PeopleApi(_apiClient);
    sharedLinksApi = SharedLinksApi(_apiClient);
    syncApi = SyncApi(_apiClient);
    systemConfigApi = SystemConfigApi(_apiClient);
    activitiesApi = ActivitiesApi(_apiClient);
    downloadApi = DownloadApi(_apiClient);
    trashApi = TrashApi(_apiClient);
    stacksApi = StacksApi(_apiClient);
    viewApi = ViewsApi(_apiClient);
    memoriesApi = MemoriesApi(_apiClient);
    sessionsApi = SessionsApi(_apiClient);
    tagsApi = TagsApi(_apiClient);
  }

  Future<String> resolveAndSetEndpoint(
    String serverUrl, {
    EndpointResolvePolicy policy = EndpointResolvePolicy.conservative,
    bool pathAlreadyProbed = false,
  }) async {
    return _enqueueEndpointSwitch(() async {
      _isSetEndpoint = true;
      try {
        final stopwatch = Stopwatch()..start();
        final normalizedEndpoint = _normalizeEndpoint(serverUrl);
        final uri = Uri.parse(normalizedEndpoint);
        final currentHost = _apiClient.basePath.isEmpty ? null : Uri.tryParse(_apiClient.basePath)?.host;
        if (currentHost != null && currentHost != uri.host) {
          await NetworkRepository.cancelInFlightHttpRequests();
        }
        _log.info(
          'endpoint_switch start '
          'host=${uri.host} '
          'probed=$pathAlreadyProbed '
          'timeoutMs=${policy.availabilityTimeout.inMilliseconds} '
          'settleMs=${policy.settleDelay.inMilliseconds}',
        );
        final endpoint = pathAlreadyProbed
            ? normalizedEndpoint
            : await resolveEndpoint(normalizedEndpoint, availabilityTimeout: policy.availabilityTimeout);
        setEndpoint(endpoint);
        try {
          await Store.put(StoreKey.serverEndpoint, endpoint);
        } on StateError catch (error, stackTrace) {
          // Non-fatal during shutdown/background teardown when DB isolate is closing.
          _log.warning('Skipping server endpoint persistence: store channel closed', error, stackTrace);
        }

        // Sync native auth cookies after Store reflects the new endpoint so cookie
        // domains match the active host (getServerUrls reads from Store).
        await updateHeaders();

        stopwatch.stop();
        _log.info(
          'endpoint_switch success '
          'endpoint=$endpoint '
          'host=${uri.host} '
          'elapsedMs=${stopwatch.elapsedMilliseconds} '
          'timeoutMs=${policy.availabilityTimeout.inMilliseconds} '
          'settleMs=${policy.settleDelay.inMilliseconds}',
        );
        return endpoint;
      } finally {
        await Future.delayed(policy.settleDelay);
        _isSetEndpoint = false;
        _log.fine('endpoint_switch unlocked');
      }
    });
  }

  Future<T> _enqueueEndpointSwitch<T>(Future<T> Function() operation) {
    final completer = Completer<T>();
    _endpointSwitchQueue = _endpointSwitchQueue.then((_) async {
      try {
        completer.complete(await operation());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  /// Takes a server URL and attempts to resolve the API endpoint.
  ///
  /// Input: [schema://]host[:port][/path]
  ///  schema - optional (default: https)
  ///  host   - required
  ///  port   - optional (default: based on schema)
  ///  path   - optional
  Future<bool> checkEndpointAvailable(
    String serverUrl, {
    Duration timeout = _endpointAvailabilityPingTimeout,
  }) {
    return _isEndpointAvailable(_normalizeEndpoint(serverUrl), timeout: timeout);
  }

  /// Probes [candidates] in parallel and activates the first reachable endpoint.
  Future<String?> activateFirstReachable(
    Iterable<String> candidates, {
    EndpointResolvePolicy policy = EndpointResolvePolicy.bootstrap,
  }) async {
    final unique = _dedupeEndpointCandidates(candidates);
    if (unique.isEmpty) {
      return null;
    }

    final winner = await _raceReachableEndpoint(
      unique,
      timeout: policy.availabilityTimeout,
    );
    if (winner == null) {
      return null;
    }

    try {
      return await resolveAndSetEndpoint(
        winner,
        policy: policy,
        pathAlreadyProbed: true,
      );
    } on ApiException catch (error) {
      _log.severe('Cannot resolve endpoint', error);
    } catch (error, stackTrace) {
      _log.severe('Cannot resolve endpoint', error, stackTrace);
    }

    return null;
  }

  List<String> _dedupeEndpointCandidates(Iterable<String> candidates) {
    final unique = <String>[];
    final seen = <String>{};
    for (final candidate in candidates) {
      if (candidate.isEmpty || !seen.add(candidate)) {
        continue;
      }
      unique.add(candidate);
    }
    return unique;
  }

  Future<String?> _raceReachableEndpoint(
    List<String> candidates, {
    required Duration timeout,
  }) async {
    final completer = Completer<String?>();
    var pending = candidates.length;

    for (final candidate in candidates) {
      unawaited(() async {
        try {
          if (await checkEndpointAvailable(candidate, timeout: timeout)) {
            if (!completer.isCompleted) {
              completer.complete(candidate);
            }
          }
        } catch (error, stackTrace) {
          _log.fine('Endpoint probe failed for $candidate', error, stackTrace);
        } finally {
          pending--;
          if (pending == 0 && !completer.isCompleted) {
            completer.complete(null);
          }
        }
      }());
    }

    return completer.future;
  }

  Future<String> resolveEndpoint(
    String serverUrl, {
    Duration availabilityTimeout = _endpointAvailabilityPingTimeout,
  }) async {
    String url = _normalizeEndpoint(serverUrl);

    if (!await _isEndpointAvailable(url, timeout: availabilityTimeout)) {
      throw ApiException(503, "Server is not reachable");
    }

    // Otherwise, assume the URL provided is the api endpoint
    return url;
  }

  String _normalizeEndpoint(String serverUrl) {
    String url = sanitizeUrl(serverUrl);
    final normalized = sanitizeUrl(_getWellKnownEndpoint(url));
    return normalized;
  }

  Future<bool> _isEndpointAvailable(String serverUrl, {required Duration timeout}) async {
    final trace = FirebasePerformanceWrapper.newTrace('endpoint_availability') ?? NoOpTrace();
    await trace.start();

    if (!serverUrl.endsWith('/api')) {
      serverUrl += '/api';
    }

    try {
      // Use a temporary ApiClient to avoid mutating the global client while probing availability.
      final tempClient = ApiClient(basePath: serverUrl, authentication: this)..client = _httpClient;
      final tempServerApi = ServerApi(tempClient);

      await tempServerApi.pingServer().timeout(timeout);
      await trace.stop();
      _log.fine(
        'endpoint_availability ok '
        'serverUrl=$serverUrl '
        'timeoutMs=${timeout.inMilliseconds}',
      );
    } on TimeoutException catch (_) {
      await trace.stop();
      _log.info(
        'endpoint_availability timeout '
        'serverUrl=$serverUrl '
        'timeoutMs=${timeout.inMilliseconds}',
      );
      return false;
    } on SocketException catch (_) {
      await trace.stop();
      _log.info(
        'endpoint_availability socket_error '
        'serverUrl=$serverUrl '
        'timeoutMs=${timeout.inMilliseconds}',
      );
      return false;
    } catch (error, stackTrace) {
      await trace.stop();
      _log.severe(
        'endpoint_availability failed '
        'serverUrl=$serverUrl '
        'timeoutMs=${timeout.inMilliseconds}',
        error,
        stackTrace,
      );
      return false;
    }
    return true;
  }

  // Temporary
  String _getWellKnownEndpoint(String baseUrl) {
    final normalized = sanitizeUrl(baseUrl);
    if (normalized.endsWith('/photos/api') || normalized.endsWith('/api')) {
      return normalized;
    }
    if (normalized.endsWith('/photos')) {
      return '$normalized/api';
    }
    return '$normalized/photos/api';
  }

  Future<void> setAccessToken(String accessToken) async {
    _accessToken = accessToken;
    await Store.put(StoreKey.accessToken, accessToken);
    await updateHeaders();
  }

  Future<void> clearAccessToken() async {
    _accessToken = null;
    await Store.delete(StoreKey.accessToken);
    await updateHeaders();
  }

  Future<void> setDeviceInfoHeader() async {
    DeviceInfoPlugin deviceInfoPlugin = DeviceInfoPlugin();

    if (Platform.isIOS) {
      final iosInfo = await deviceInfoPlugin.iosInfo;
      authenticationApi.apiClient.addDefaultHeader('deviceModel', iosInfo.utsname.machine);
      authenticationApi.apiClient.addDefaultHeader('deviceType', 'iOS');
    } else if (Platform.isAndroid) {
      final androidInfo = await deviceInfoPlugin.androidInfo;
      authenticationApi.apiClient.addDefaultHeader('deviceModel', androidInfo.model);
      authenticationApi.apiClient.addDefaultHeader('deviceType', 'Android');
    } else {
      authenticationApi.apiClient.addDefaultHeader('deviceModel', 'Unknown');
      authenticationApi.apiClient.addDefaultHeader('deviceType', 'Unknown');
    }
  }

  static Map<String, String> getRequestHeaders() {
    var customHeadersStr = Store.get(StoreKey.customHeaders, "");
    var header = <String, String>{};
    if (customHeadersStr.isEmpty) {
      return header;
    }

    var customHeaders = jsonDecode(customHeadersStr) as Map;
    customHeaders.forEach((key, value) {
      header[key] = value;
    });

    return header;
  }

  /// Custom headers plus the current access token for transports that do not use
  /// [NetworkRepository.setHeaders] (e.g. socket.io extra headers).
  static Map<String, String> getAuthenticatedRequestHeaders() {
    final headers = Map<String, String>.from(getRequestHeaders());
    final token = Store.tryGet(StoreKey.accessToken);
    if (token != null && token.isNotEmpty) {
      headers['Authorization'] = 'Bearer $token';
    }
    return headers;
  }

  static List<String> getServerUrls() {
    final urls = <String>[];
    final serverEndpoint = Store.tryGet(StoreKey.serverEndpoint);
    if (serverEndpoint != null && serverEndpoint.isNotEmpty) {
      urls.add(serverEndpoint);
    }
    final localEndpoint = Store.tryGet(StoreKey.localEndpoint);
    if (localEndpoint != null && localEndpoint.isNotEmpty) {
      urls.add(localEndpoint);
    }
    final externalJson = Store.tryGet(StoreKey.externalEndpointList);
    if (externalJson != null) {
      final List<dynamic> list = jsonDecode(externalJson);
      for (final entry in list) {
        final url = AuxilaryEndpoint.fromJson(entry).url;
        if (url.isNotEmpty) urls.add(url);
      }
    }
    return urls;
  }

  Future<void> updateHeaders() async {
    _log.fine(
      '[auth-path] cookie sync store=${Store.tryGet(StoreKey.serverEndpoint)} api=${_apiClient.basePath}',
    );
    await NetworkRepository.setHeaders(
      getRequestHeaders(),
      getServerUrls(),
      token: _accessToken ?? Store.tryGet(StoreKey.accessToken),
    );
    if (_httpClientInitialized) {
      _syncHttpClientFromRepository();
    }
    _apiClient.client = _httpClient;
  }

  @override
  Future<void> applyToParams(List<QueryParam> queryParams, Map<String, String> headerParams) {
    return Future<void>(() {
      var headers = ApiService.getRequestHeaders();
      headerParams.addAll(headers);
    });
  }

  ApiClient get apiClient => _apiClient;

  Client get httpClient {
    _initHttpClient();
    return _httpClient;
  }
  String? get transientAccessToken => _accessToken;
}

class EndpointResolvePolicy {
  const EndpointResolvePolicy({
    this.availabilityTimeout = const Duration(seconds: 15),
    this.settleDelay = const Duration(milliseconds: 1500),
  });

  final Duration availabilityTimeout;
  final Duration settleDelay;

  static const EndpointResolvePolicy conservative = EndpointResolvePolicy();

  static const EndpointResolvePolicy bootstrap = EndpointResolvePolicy(
    availabilityTimeout: Duration(seconds: 5),
    settleDelay: Duration(milliseconds: 200),
  );
}
