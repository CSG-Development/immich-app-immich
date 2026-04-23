import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:http/http.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/auth/auxilary_endpoint.model.dart';
import 'package:immich_mobile/services/firebase_performance_wrapper.dart';
import 'package:immich_mobile/services/auxiliary_endpoint_store.service.dart';
import 'package:immich_mobile/models/connection_state.model.dart';
import 'package:immich_mobile/utils/certificates_pinning/cert_pinning_config.dart';
import 'package:immich_mobile/utils/certificates_pinning/http_cert_pinning_manager.dart';
import 'package:immich_mobile/utils/backup_trace.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:immich_mobile/utils/user_agent.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

class ConnectionRecoveryInterceptor extends BaseClient {
  final Client _inner;
  final Function(String) _onConnectionError;
  final void Function(String, int)? _onRequestSuccess;

  ConnectionRecoveryInterceptor(this._inner, this._onConnectionError, {void Function(String, int)? onRequestSuccess})
    : _onRequestSuccess = onRequestSuccess;

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
    try {
      final response = await _inner.send(request);
      _onRequestSuccess?.call(request.url.toString(), response.statusCode);
      return response;
    } catch (e) {
      if (_isConnectionError(e)) {
        _onConnectionError(request.url.toString());
      }
      rethrow;
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
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'TLS/SSL communication failed: ${request.method} ${request.url}',
        e,
        StackTrace.current,
      );
    } on SocketException catch (e) {
      await httpMetric.stop();
      throw ApiException.withInner(
        HttpStatus.badRequest,
        'Socket operation failed: ${request.method} ${request.url}',
        e,
        StackTrace.current,
      );
    } catch (e) {
      await httpMetric.stop();
      rethrow;
    }
  }
}

enum _EndpointProbeKind { local, remote }

class _EndpointProbeResult {
  final String endpoint;
  final String host;
  final _EndpointProbeKind kind;

  const _EndpointProbeResult({
    required this.endpoint,
    required this.host,
    required this.kind,
  });
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

  bool _isSetEndpoint = false;
  Future<void> _endpointResolutionQueue = Future<void>.value();
  DateTime? _lastConnectedStateSignalAt;
  static const Duration _connectedStateSignalDebounce = Duration(seconds: 3);

  /// Optional hook (set from main tab shell): run Curator device re-detection after
  /// [ConnectionStatus.reconnecting] is published.
  void Function()? curatorNetworkForceReconnectHandler;

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
      onRequestSuccess: _handleConnectionSuccess,
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

  void _handleConnectionSuccess(String succeededUrl, int statusCode) {
    // Any successful response from the active endpoint can clear reconnect UI.
    final isConnectivitySuccess = (statusCode >= 200 && statusCode < 300) || statusCode == 304;
    if (!isConnectivitySuccess || _isSetEndpoint) {
      return;
    }

    final isAuthenticated = Store.get(StoreKey.accessToken, "").isNotEmpty;
    if (!isAuthenticated) {
      return;
    }

    final activeEndpoint = Store.tryGet(StoreKey.serverEndpoint);
    if (activeEndpoint != null && activeEndpoint.isNotEmpty && !succeededUrl.startsWith(activeEndpoint)) {
      return;
    }

    final now = DateTime.now();
    final lastSignalAt = _lastConnectedStateSignalAt;
    if (lastSignalAt != null && now.difference(lastSignalAt) < _connectedStateSignalDebounce) {
      return;
    }
    _lastConnectedStateSignalAt = now;
    notifyConnectionState(
      const ConnectionState(
        status: ConnectionStatus.connected,
        connectionType: ConnectionType.api,
      ),
    );
  }

  void notifyConnectionState(ConnectionState state) {
    try {
      if (!_connectionStateController.isClosed) {
        _connectionStateController.add(state);
      }
    } catch (error, stackTrace) {
      _log.warning("Failed to notify connection state (non-critical)", error, stackTrace);
    }
  }

  Future<bool> validateAuxilaryServerUrl(String url) async {
    final httpclient = HttpClient();
    bool isValid = false;

    try {
      final uri = Uri.parse('$url/users/me');
      final request = await httpclient.getUrl(uri);

      // add auth token + any configured custom headers
      final customHeaders = ApiService.getRequestHeaders();
      customHeaders.forEach((key, value) {
        request.headers.add(key, value);
      });

      final response = await request.close();
      if (response.statusCode == 200) {
        isValid = true;
      }
    } catch (error) {
      _log.severe("Error validating auxiliary endpoint", error);
    } finally {
      httpclient.close();
    }

    return isValid;
  }

  Future<T> _enqueueEndpointResolution<T>(Future<T> Function() action) {
    final completer = Completer<T>();
    _endpointResolutionQueue = _endpointResolutionQueue.catchError((_) {}).then((_) async {
      try {
        completer.complete(await action());
      } catch (error, stackTrace) {
        completer.completeError(error, stackTrace);
      }
    });
    return completer.future;
  }

  Future<String?> setOpenApiServiceEndpoint({
    List<String>? auxiliaryEndpoints,
    String? runId,
    bool allowLocalProbe = true,
  }) {
    return _enqueueEndpointResolution(
      () => _setOpenApiServiceEndpointInternal(
        auxiliaryEndpoints: auxiliaryEndpoints,
        runId: runId,
        allowLocalProbe: allowLocalProbe,
      ),
    );
  }

  Future<String?> _setOpenApiServiceEndpointInternal({
    List<String>? auxiliaryEndpoints,
    String? runId,
    bool allowLocalProbe = true,
  }) async {
    // Prevent connection state notifications during endpoint switching
    _isSetEndpoint = true;

    try {
      final sw = Stopwatch()..start();
      final traceRunId = runId ?? BackupTrace.newRunId();
      // Keep the currently configured endpoint as a fallback
      final previousEndpoint = Store.tryGet(StoreKey.serverEndpoint);
      String? endpoint;
      var resolutionPath = 'failed';
      final hasWifi = await _hasWifiConnectivity();
      final effectiveAllowLocalProbe = allowLocalProbe && hasWifi;

      if (!effectiveAllowLocalProbe) {
        final skipReason = allowLocalProbe ? 'no_wifi' : 'caller_disabled';
        _log.info(
          'upload_telemetry source=api_service stage=local_probe decision=skipped reason=$skipReason '
          'allowLocalProbe=$allowLocalProbe hasWifi=$hasWifi',
        );
        logBackupTrace(
          _log,
          level: Level.INFO,
          event: BackupTraceEvent.endpointSelected,
          phase: BackupTracePhase.endpoint,
          step: 'ENDPOINT_LOCAL_SKIPPED',
          source: 'NETWORK_SWITCH',
          appState: 'RESUMED',
          trigger: 'endpoint_resolve',
          status: BackupTraceStatus.retry,
          reasonCode: allowLocalProbe ? 'NO_WIFI_SKIP_LOCAL' : 'LOCAL_PROBE_DISABLED',
          runId: traceRunId,
          elapsedMs: sw.elapsedMilliseconds,
        );
      }

      try {
        final localCandidates = <String>[
          if (effectiveAllowLocalProbe && auxiliaryEndpoints != null) ...auxiliaryEndpoints,
        ];
        if (effectiveAllowLocalProbe) {
          final local = _getLocalEndpoint();
          if (local != null && local.isNotEmpty) {
            localCandidates.add(local);
          }
        }

        List<String> remoteCandidates = const [];
        try {
          final endpointList = getExternalEndpointList();
          remoteCandidates = _sortRemoteCandidatesForPriority(endpointList).map((e) => e.url).toList(growable: false);
        } catch (error, stackTrace) {
          _log.severe("Cannot get external endpoint", error, stackTrace);
        }
        if (previousEndpoint != null && previousEndpoint.isNotEmpty && !remoteCandidates.contains(previousEndpoint)) {
          // Keep the currently active/stored endpoint as a recovery candidate.
          // This avoids "no candidates" dead-ends after transient network flips.
          remoteCandidates = <String>[...remoteCandidates, previousEndpoint];
        }

        _log.info(
          'upload_telemetry source=api_service stage=endpoint_probe '
          'localCandidates=${localCandidates.length} remoteCandidates=${remoteCandidates.length} '
          'allowLocalProbe=$allowLocalProbe hasWifi=$hasWifi effectiveAllowLocalProbe=$effectiveAllowLocalProbe',
        );

        final winner = await _probeEndpointCandidates(
          localCandidates: localCandidates,
          remoteCandidates: remoteCandidates,
          runId: traceRunId,
        );

        if (winner != null) {
          endpoint = await _activateResolvedEndpoint(winner.endpoint, host: winner.host, stopwatch: sw);
          resolutionPath = winner.kind == _EndpointProbeKind.local ? 'local' : 'remote';
        }

        if (endpoint != null && winner != null) {
          final selectedKind = winner.kind == _EndpointProbeKind.local ? 'local' : 'remote';
          final selectedReasonCode = winner.kind == _EndpointProbeKind.local
              ? 'ENDPOINT_LOCAL_SELECTED'
              : 'ENDPOINT_REMOTE_SELECTED';
          final selectedStep = winner.kind == _EndpointProbeKind.local ? 'ENDPOINT_LOCAL_OK' : 'ENDPOINT_REMOTE_OK';

          _log.info('upload_telemetry source=api_service stage=endpoint_selected kind=$selectedKind endpoint=$endpoint');
          logBackupTrace(
            _log,
            level: Level.INFO,
            event: BackupTraceEvent.endpointSelected,
            phase: BackupTracePhase.endpoint,
            step: selectedStep,
            source: 'NETWORK_SWITCH',
            appState: 'RESUMED',
            trigger: 'endpoint_resolve',
            status: BackupTraceStatus.ok,
            reasonCode: selectedReasonCode,
            runId: traceRunId,
            elapsedMs: sw.elapsedMilliseconds,
          );
        } else {}
        return endpoint;
      } catch (error, stackTrace) {
        _log.severe("Endpoint candidate probing failed", error, stackTrace);
      }

      // If everything failed, fall back to the previously used endpoint (if any)
      if (endpoint == null && previousEndpoint != null && previousEndpoint.isNotEmpty) {
        dPrint(() => 'Falling back to previous endpoint: $previousEndpoint');
        await _resolveAndSetEndpointInternal(previousEndpoint);
        endpoint = previousEndpoint;
        resolutionPath = 'fallback_previous';
        _log.warning(
          'upload_telemetry source=api_service stage=endpoint_selected kind=fallback_previous endpoint=$endpoint',
        );
        logBackupTrace(
          _log,
          level: Level.WARNING,
          event: BackupTraceEvent.endpointFallback,
          phase: BackupTracePhase.endpoint,
          step: 'ENDPOINT_FALLBACK_PREVIOUS',
          source: 'NETWORK_SWITCH',
          appState: 'RESUMED',
          trigger: 'endpoint_resolve',
          status: BackupTraceStatus.retry,
          reasonCode: 'ENDPOINT_FALLBACK_PREVIOUS',
          runId: traceRunId,
          elapsedMs: sw.elapsedMilliseconds,
        );
      }

      if (endpoint == null) {
        _log.warning(
          'upload_telemetry source=api_service stage=endpoint_resolution_final '
          'outcome=failed resolutionPath=$resolutionPath previousEndpoint=$previousEndpoint',
        );
      } else {
        _log.info(
          'upload_telemetry source=api_service stage=endpoint_resolution_final '
          'outcome=success resolutionPath=$resolutionPath endpoint=$endpoint previousEndpoint=$previousEndpoint',
        );
        final isAuthenticated = Store.get(StoreKey.accessToken, "").isNotEmpty;
        if (isAuthenticated) {
          notifyConnectionState(
            const ConnectionState(
              status: ConnectionStatus.connected,
              connectionType: ConnectionType.api,
            ),
          );
        }
      }
      return endpoint;
    } catch (error) {
      rethrow;
    } finally {
      // Give the new endpoint a brief settle time before clearing errors
      await Future.delayed(const Duration(milliseconds: 1500));
      // Allow connection state notifications again
      _isSetEndpoint = false;
    }
  }

  Future<_EndpointProbeResult?> _probeEndpointCandidates({
    required List<String> localCandidates,
    required List<String> remoteCandidates,
    required String runId,
  }) async {
    final probeTasks = <Future<_EndpointProbeResult?>>[
      if (localCandidates.isNotEmpty)
        _probeCandidateList(localCandidates, kind: _EndpointProbeKind.local, runId: runId),
      if (remoteCandidates.isNotEmpty)
        _probeCandidateList(remoteCandidates, kind: _EndpointProbeKind.remote, runId: runId),
    ];

    if (probeTasks.isEmpty) {
      return null;
    }

    final completer = Completer<_EndpointProbeResult?>();
    var pending = probeTasks.length;

    for (final task in probeTasks) {
      task
          .then((result) {
            if (!completer.isCompleted && result != null) {
              completer.complete(result);
              return;
            }
            pending--;
            if (pending == 0 && !completer.isCompleted) {
              completer.complete(null);
            }
          })
          .catchError((_) {
            pending--;
            if (pending == 0 && !completer.isCompleted) {
              completer.complete(null);
            }
          });
    }

    return completer.future;
  }

  Future<_EndpointProbeResult?> _probeCandidateList(
    List<String> candidates, {
    required _EndpointProbeKind kind,
    required String runId,
  }) async {
    for (final candidate in candidates) {
      if (candidate.isEmpty) {
        continue;
      }
      final result = await _probeSingleCandidate(candidate, kind: kind, runId: runId);
      if (result != null) {
        return result;
      }
    }
    return null;
  }

  Future<_EndpointProbeResult?> _probeSingleCandidate(
    String candidate, {
    required _EndpointProbeKind kind,
    required String runId,
  }) async {
    final candidateKind = kind == _EndpointProbeKind.local ? 'local' : 'remote';
    _log.fine(
      'upload_telemetry source=api_service stage=endpoint_probe_candidate '
      'decision=attempt kind=$candidateKind candidate=$candidate',
    );
    try {
      final uri = Uri.parse(candidate);
      await certPinning.registerHostTrustedChain(host: uri.host, port: uri.port);
      final endpoint = await resolveEndpoint(candidate, suppressConnectionRecoveryNotifications: true);
      return _EndpointProbeResult(endpoint: endpoint, host: uri.host, kind: kind);
    } catch (error, stackTrace) {
      _log.warning(
        'upload_telemetry source=api_service stage=endpoint_probe_candidate '
        'decision=failed kind=$candidateKind candidate=$candidate errorType=${error.runtimeType}',
      );
      if (kind == _EndpointProbeKind.local) {
        _log.severe("Cannot set local endpoint", error, stackTrace);
        logBackupTrace(
          _log,
          level: Level.SEVERE,
          event: BackupTraceEvent.endpointLocalFail,
          phase: BackupTracePhase.endpoint,
          step: 'ENDPOINT_LOCAL_FAIL',
          source: 'NETWORK_SWITCH',
          appState: 'RESUMED',
          trigger: 'endpoint_resolve',
          status: BackupTraceStatus.fail,
          reasonCode: 'ENDPOINT_LOCAL_CERT_FAIL',
          runId: runId,
          extra: {'endpoint': candidate},
          error: error,
          stackTrace: stackTrace,
        );
      } else {
        _log.severe("Cannot resolve endpoint $candidate", error, stackTrace);
      }
      return null;
    }
  }

  Future<String> _activateResolvedEndpoint(
    String endpoint, {
    required String host,
    required Stopwatch stopwatch,
  }) async {
    setEndpoint(endpoint);
    Store.put(StoreKey.serverEndpoint, endpoint);
    _log.info(
      'upload_telemetry source=api_service stage=resolve_and_set endpoint=$endpoint '
      'host=$host elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    return endpoint;
  }

  Future<bool> _hasWifiConnectivity() async {
    try {
      final connectivity = await Connectivity().checkConnectivity();
      return connectivity.contains(ConnectivityResult.wifi);
    } catch (error, stackTrace) {
      _log.warning(
        'Unable to determine connectivity while resolving endpoint. '
        'Disabling local probe for safety.',
        error,
        stackTrace,
      );
      return false;
    }
  }

  /// Attempts to connect to the local endpoint.
  /// Returns the endpoint URL if successful, null otherwise.
  Future<String?> tryLocalEndpoint(String? endpoints, {String? runId}) async {
    try {
      final localEndpoint = endpoints ?? _getLocalEndpoint();
      if (localEndpoint == null || localEndpoint.isEmpty) {
        _log.fine("Local endpoint is not set");
        return null;
      }

      final resolvedEndpoint = await resolveAndSetEndpoint(localEndpoint);
      return resolvedEndpoint;
    } catch (error, stackTrace) {
      _log.severe("Cannot set local endpoint", error, stackTrace);
      logBackupTrace(
        _log,
        level: Level.SEVERE,
        event: BackupTraceEvent.endpointLocalFail,
        phase: BackupTracePhase.endpoint,
        step: 'ENDPOINT_LOCAL_FAIL',
        source: 'NETWORK_SWITCH',
        appState: 'RESUMED',
        trigger: 'endpoint_resolve',
        status: BackupTraceStatus.fail,
        reasonCode: 'ENDPOINT_LOCAL_CERT_FAIL',
        runId: runId,
        extra: {'endpoint': endpoints ?? _getLocalEndpoint() ?? '<null>'},
        error: error,
        stackTrace: stackTrace,
      );
    }

    return null;
  }

  /// Compatibility wrapper with singular argument naming.
  Future<String?> tryLocalEndpointCandidate(String? endpoint, {String? runId}) =>
      tryLocalEndpoint(endpoint, runId: runId);

  /// Attempts to connect to remote endpoints from the external endpoint list.
  /// Returns the first successful endpoint URL, or null if all fail.
  Future<String?> tryRemoteEndpoints({String? runId}) async {
    List<AuxilaryEndpoint> endpointList;

    try {
      endpointList = getExternalEndpointList();
    } catch (error, stackTrace) {
      _log.severe("Cannot get external endpoint", error, stackTrace);
      return null;
    }

    final sortedEndpoints = _sortRemoteCandidatesForPriority(endpointList);
    for (final endpoint in sortedEndpoints) {
      try {
        final resolvedEndpoint = await resolveAndSetEndpoint(endpoint.url);
        return resolvedEndpoint;
      } on ApiException catch (error) {
        _log.severe("Cannot resolve endpoint ${endpoint.url}", error);
        continue;
      } catch (error, stackTrace) {
        _log.severe("Auxiliary server ${endpoint.url} is not valid", error, stackTrace);
        continue;
      }
    }

    return null;
  }

  List<AuxilaryEndpoint> _sortRemoteCandidatesForPriority(List<AuxilaryEndpoint> endpoints) {
    final directLike = <AuxilaryEndpoint>[];
    final relayLike = <AuxilaryEndpoint>[];

    for (final endpoint in endpoints) {
      if (_isRelayLikeEndpoint(endpoint.url)) {
        relayLike.add(endpoint);
      } else {
        directLike.add(endpoint);
      }
    }

    return <AuxilaryEndpoint>[...directLike, ...relayLike];
  }

  bool _isRelayLikeEndpoint(String endpoint) {
    final uri = Uri.tryParse(endpoint);
    if (uri == null) {
      return false;
    }

    final host = uri.host.toLowerCase();
    final path = uri.path.toLowerCase();
    return host.contains('relay') ||
        host.contains('proxy') ||
        host.contains('tunnel') ||
        path.contains('relay') ||
        path.contains('proxy') ||
        path.contains('tunnel');
  }

  String? _getLocalEndpoint() {
    return Store.tryGet(StoreKey.localEndpoint);
  }

  /// Gets the list of external endpoints from storage.
  /// Returns an empty list if none are configured.
  List<AuxilaryEndpoint> getExternalEndpointList() => AuxiliaryEndpointStoreService.loadAll();

  /// Compatibility wrapper for clearer naming.
  Future<String?> resolveAndActivateOpenApiEndpoint({List<String>? auxiliaryEndpoints, String? runId}) =>
      setOpenApiServiceEndpoint(auxiliaryEndpoints: auxiliaryEndpoints, runId: runId);

  void setEndpoint(String endpoint) {
    // Rebuild HTTP clients when changing endpoints to drop stale keep-alive connections
    _initHttpClient();

    _apiClient = ApiClient(basePath: endpoint, authentication: this);
    _setUserAgentHeader();
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

  Future<void> _setUserAgentHeader() async {
    final userAgent = await getUserAgentString();
    _apiClient.addDefaultHeader('User-Agent', userAgent);
  }

  Future<String> resolveAndSetEndpoint(String serverUrl) async {
    return _enqueueEndpointResolution(() => _resolveAndSetEndpointInternal(serverUrl));
  }

  Future<String> _resolveAndSetEndpointInternal(String serverUrl) async {
    final stopwatch = Stopwatch()..start();
    final uri = Uri.parse(serverUrl);
    await certPinning.registerHostTrustedChain(host: uri.host, port: uri.port);
    final endpoint = await resolveEndpoint(serverUrl);
    setEndpoint(endpoint);

    // Save in local database for next startup
    Store.put(StoreKey.serverEndpoint, endpoint);
    stopwatch.stop();
    _log.info(
      'upload_telemetry source=api_service stage=resolve_and_set endpoint=$endpoint '
      'host=${uri.host} elapsedMs=${stopwatch.elapsedMilliseconds}',
    );
    final isAuthenticated = Store.get(StoreKey.accessToken, "").isNotEmpty;
    if (isAuthenticated) {
      notifyConnectionState(
        const ConnectionState(
          status: ConnectionStatus.connected,
          connectionType: ConnectionType.api,
        ),
      );
    }
    return endpoint;
  }

  /// Takes a server URL and attempts to resolve the API endpoint.
  ///
  /// Input: [schema://]host[:port][/path]
  ///  schema - optional (default: https)
  ///  host   - required
  ///  port   - optional (default: based on schema)
  ///  path   - optional
  Future<String> resolveEndpoint(String serverUrl, {bool suppressConnectionRecoveryNotifications = false}) async {
    String url = sanitizeUrl(serverUrl);

    // Check for /.well-known/immich
    final wellKnownEndpoint = await _getWellKnownEndpoint(url);
    if (wellKnownEndpoint.isNotEmpty) {
      url = sanitizeUrl(wellKnownEndpoint);
    }

    if (!await _isEndpointAvailable(url, suppressConnectionRecoveryNotifications: suppressConnectionRecoveryNotifications)) {
      throw ApiException(503, "Server is not reachable");
    }

    // Otherwise, assume the URL provided is the api endpoint
    return url;
  }

  Future<bool> _isEndpointAvailable(
    String serverUrl, {
    bool suppressConnectionRecoveryNotifications = false,
  }) async {
    final trace = FirebasePerformanceWrapper.newTrace('endpoint_availability') ?? NoOpTrace();
    await trace.start();
    Client? plainProbeClient;

    if (!serverUrl.endsWith('/api')) {
      serverUrl += '/api';
    }

    try {
      // Use a temporary ApiClient to avoid mutating the global client while probing availability.
      // When probing in parallel, use a plain client so failed probes do not publish reconnecting
      // state via ConnectionRecoveryInterceptor and inadvertently keep reconnect UI visible.
      final probeHttpClient = suppressConnectionRecoveryNotifications ? (plainProbeClient = Client()) : _httpClient;
      final tempClient = ApiClient(basePath: serverUrl, authentication: this)..client = probeHttpClient;
      final tempServerApi = ServerApi(tempClient);

      // Keep probe timeout bounded to avoid long queue stalls under poor networks.
      await tempServerApi.pingServer().timeout(const Duration(seconds: 12));
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
    } finally {
      plainProbeClient?.close();
    }
    return true;
  }

  // Temporary
  Future<String> _getWellKnownEndpoint(String baseUrl) async {
    final normalized = sanitizeUrl(baseUrl);
    final uri = Uri.tryParse(normalized);
    if (uri == null) {
      return normalized;
    }

    final segments = uri.pathSegments.where((segment) => segment.isNotEmpty).toList(growable: false);
    if (segments.isEmpty) {
      // Host-only URL: use the legacy photos API location.
      return '$normalized/photos/api';
    }

    if (segments.length >= 2 &&
        segments[segments.length - 2].toLowerCase() == 'photos' &&
        segments.last.toLowerCase() == 'api') {
      // Already points to /photos/api.
      return normalized;
    }

    if (segments.last.toLowerCase() == 'api') {
      // Already points to an API endpoint.
      return normalized;
    }

    if (segments.last.toLowerCase() == 'photos') {
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
