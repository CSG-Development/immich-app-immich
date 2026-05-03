import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:http/http.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/services/firebase_performance_wrapper.dart';
import 'package:immich_mobile/models/connection_state.model.dart';
import 'package:immich_mobile/utils/certificates_pinning/cert_pinning_config.dart';
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

  bool _isConnectionError(dynamic error) {
    return error is SocketException ||
        error is TimeoutException ||
        error is TlsException ||
        error is HandshakeException ||
        error is HttpException ||
        (error is ClientException && error.message.contains('Connection') == true);
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
    _inner.close();
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
      _log.warning(
        '[HTTP] TLS failure ${request.method} ${request.url}',
        e,
      );
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'TLS/SSL communication failed: ${request.method} ${request.url}',
        e,
        StackTrace.current,
      );
    } on SocketException catch (e) {
      await httpMetric.stop();
      _log.warning(
        '[HTTP] Socket failure ${request.method} ${request.url}',
        e,
      );
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'Socket operation failed: ${request.method} ${request.url}',
        e,
        StackTrace.current,
      );
    } catch (e) {
      await httpMetric.stop();
      _log.warning(
        '[HTTP] Unhandled transport failure ${request.method} ${request.url}',
        e,
      );
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
  late OAuthApi oAuthApi;
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
  late ViewApi viewApi;
  late MemoriesApi memoriesApi;
  late SessionsApi sessionsApi;
  late TagsApi tagsApi;

  final _log = Logger("ApiService");
  final StreamController<ConnectionState> _connectionStateController = StreamController<ConnectionState>.broadcast();
  Stream<ConnectionState> get connectionStateChanges => _connectionStateController.stream;
  ConnectionStatus _lastConnectionStatus = ConnectionStatus.connected;

  static const Duration _endpointAvailabilityPingTimeout = Duration(seconds: 15);
  static const Duration _endpointSwitchSettleDelay = Duration(milliseconds: 1500);

  bool _isSetEndpoint = false;
  Future<void> _endpointSwitchQueue = Future<void>.value();

  /// Optional hook (set from main tab shell): run Curator device re-detection after
  /// [ConnectionStatus.reconnecting] is published.
  void Function()? curatorNetworkForceReconnectHandler;
  void Function(String, Duration, bool isHard)? curatorNetworkSlowRequestHandler;

  final HttpCertPinningManager certPinning;

  ApiService({required this.certPinning}) {
    _initHttpClient();
    // Initialize with empty endpoint first, then restore the last known endpoint (if any).
    setEndpoint('');
    final endpoint = Store.tryGet(StoreKey.serverEndpoint);
    if (endpoint != null && endpoint.isNotEmpty) {
      setEndpoint(endpoint);
    }
  }

  static instantiate() async {
    final certPinning = HttpCertPinningManager(
      config: const CertPinningConfig(allowFallback: false, installRootsInSecurityContext: true),
    );

    await certPinning.initialize();

    return ApiService(certPinning: certPinning);
  }

  void _initHttpClient() {
    // Recreate clients to avoid reusing keep-alive connections when switching endpoints
    if (_httpClientInitialized) {
      _connectionRecoveryInterceptor.close();
      _baseClient.close();
    }

    _baseClient = Client();
    _connectionRecoveryInterceptor = ConnectionRecoveryInterceptor(
      _baseClient,
      _handleConnectionError,
      onRequestSuccess: _handleRequestSuccess,
      onSlowRequest: _handleSlowRequest,
    );
    _httpClient = PerformanceHttpClient(_connectionRecoveryInterceptor);
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

    final isAuthenticated = Store.get(StoreKey.accessToken, "").isNotEmpty;
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

    final isAuthenticated = Store.get(StoreKey.accessToken, "").isNotEmpty;
    if (!isAuthenticated) {
      return;
    }

    _log.info('Publishing connected state after successful request: $requestUrl');
    notifyConnectionState(
      const ConnectionState(
        status: ConnectionStatus.connected,
        connectionType: ConnectionType.api,
      ),
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
    // Rebuild HTTP clients when changing endpoints to drop stale keep-alive connections
    _initHttpClient();

    _apiClient = ApiClient(basePath: endpoint, authentication: this);
    _apiClient.client = _httpClient;
    if (_accessToken != null) {
      // ignore: discarded_futures
      setAccessToken(_accessToken!);
    }
    usersApi = UsersApi(_apiClient);
    authenticationApi = AuthenticationApi(_apiClient);
    oAuthApi = OAuthApi(_apiClient);
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
    viewApi = ViewApi(_apiClient);
    memoriesApi = MemoriesApi(_apiClient);
    sessionsApi = SessionsApi(_apiClient);
    tagsApi = TagsApi(_apiClient);
  }

  Future<String> resolveAndSetEndpoint(String serverUrl) async {
    return _enqueueEndpointSwitch(() async {
      _isSetEndpoint = true;
      try {
        final stopwatch = Stopwatch()..start();
        final uri = Uri.parse(serverUrl);
        await certPinning.registerHostTrustedChain(host: uri.host, port: uri.port);
        final endpoint = await resolveEndpoint(serverUrl);
        setEndpoint(endpoint);
        try {
          await Store.put(StoreKey.serverEndpoint, endpoint);
        } on StateError catch (error, stackTrace) {
          // Non-fatal during shutdown/background teardown when DB isolate is closing.
          _log.warning('Skipping server endpoint persistence: store channel closed', error, stackTrace);
        }

        stopwatch.stop();
        _log.info(
          'upload_telemetry source=api_service stage=resolve_and_set endpoint=$endpoint '
          'host=${uri.host} elapsedMs=${stopwatch.elapsedMilliseconds}',
        );
        return endpoint;
      } finally {
        await Future.delayed(_endpointSwitchSettleDelay);
        _isSetEndpoint = false;
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
  Future<String> resolveEndpoint(String serverUrl) async {
    String url = _normalizeEndpoint(serverUrl);

    if (!await _isEndpointAvailable(url)) {
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

  Future<bool> _isEndpointAvailable(String serverUrl) async {
    final trace = FirebasePerformanceWrapper.newTrace('endpoint_availability') ?? NoOpTrace();
    await trace.start();

    if (!serverUrl.endsWith('/api')) {
      serverUrl += '/api';
    }

    try {
      // Use a temporary ApiClient to avoid mutating the global client while probing availability.
      final tempClient = ApiClient(basePath: serverUrl, authentication: this)..client = _httpClient;
      final tempServerApi = ServerApi(tempClient);

      await tempServerApi.pingServer().timeout(_endpointAvailabilityPingTimeout);
      await trace.stop();
    } on TimeoutException catch (_) {
      await trace.stop();
      return false;
    } on SocketException catch (_) {
      await trace.stop();
      return false;
    } catch (error, stackTrace) {
      await trace.stop();
      _log.severe("Error while checking server availability", error, stackTrace);
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
    var accessToken = Store.get(StoreKey.accessToken, "");
    var customHeadersStr = Store.get(StoreKey.customHeaders, "");
    var header = <String, String>{};
    if (accessToken.isNotEmpty) {
      header['x-immich-user-token'] = accessToken;
    }

    if (customHeadersStr.isEmpty) {
      return header;
    }

    var customHeaders = jsonDecode(customHeadersStr) as Map;
    customHeaders.forEach((key, value) {
      header[key] = value;
    });

    return header;
  }

  @override
  Future<void> applyToParams(List<QueryParam> queryParams, Map<String, String> headerParams) {
    return Future<void>(() {
      var headers = ApiService.getRequestHeaders();
      headerParams.addAll(headers);
    });
  }

  ApiClient get apiClient => _apiClient;
}
