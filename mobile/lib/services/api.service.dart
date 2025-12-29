import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:firebase_performance/firebase_performance.dart';
import 'package:http/http.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/auth/auxilary_endpoint.model.dart';
import 'package:immich_mobile/services/firebase_performance_wrapper.dart';
import 'package:immich_mobile/models/connection_state.model.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:immich_mobile/utils/user_agent.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

class ConnectionRecoveryInterceptor extends BaseClient {
  final Client _inner;
  final Function(String) _onConnectionError;

  ConnectionRecoveryInterceptor(this._inner, this._onConnectionError);

  bool _isConnectionError(dynamic error) {
    return error is SocketException ||
        error is TimeoutException ||
        error is TlsException ||
        error is HandshakeException ||
        error is HttpException ||
        (error is ClientException &&
            error.message.contains('Connection') == true);
  }

  @override
  Future<StreamedResponse> send(BaseRequest request) async {
    try {
      return await _inner.send(request);
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

  ApiService() {
    _initHttpClient();
    // Initialize with empty endpoint first, then restore the last known endpoint (if any).
    setEndpoint('');
    final endpoint = Store.tryGet(StoreKey.serverEndpoint);
    if (endpoint != null && endpoint.isNotEmpty) {
      setEndpoint(endpoint);
    }
  }

  void _initHttpClient() {
    // Recreate clients to avoid reusing keep-alive connections when switching endpoints
    if (_httpClientInitialized) {
      _connectionRecoveryInterceptor.close();
      _baseClient.close();
    }

    _baseClient = Client();
    _connectionRecoveryInterceptor = ConnectionRecoveryInterceptor(_baseClient, _handleConnectionError);
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
    if (activeEndpoint != null &&
        activeEndpoint.isNotEmpty &&
        !failedUrl.startsWith(activeEndpoint)) {
      dPrint(() => '_handleConnectionError: Skipping notification - failed URL does not match active endpoint $activeEndpoint');
      return;
    }

    final isAuthenticated = Store.get(StoreKey.accessToken, "").isNotEmpty;
    if (!isAuthenticated) {
      dPrint(() => '_handleConnectionError: Skipping notification - not authenticated');
      return;
    }
    
    notifyConnectionState(ConnectionState(
      status: ConnectionStatus.reconnecting,
      lastErrorUrl: failedUrl,
      lastErrorTime: DateTime.now(),
      connectionType: ConnectionType.api,
    ));
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

  Future<String?> setOpenApiServiceEndpoint({List<String>? auxiliaryEndpoints}) async {
    // Prevent connection state notifications during endpoint switching
    _isSetEndpoint = true;

    try {
      // Keep the currently configured endpoint as a fallback
      final previousEndpoint = Store.tryGet(StoreKey.serverEndpoint);
      String? endpoint;

      if (auxiliaryEndpoints != null && auxiliaryEndpoints.isNotEmpty) {
        for (final auxiliaryEndpoint in auxiliaryEndpoints) {
          endpoint = await _setLocalConnection(endpoint: auxiliaryEndpoint);
          if (endpoint != null) {
            return endpoint;
          }
        }
      }

      // Try local connection first
      endpoint = await _setLocalConnection();
      if (endpoint != null) {
        return endpoint;
      }

      try {
        endpoint ??= await _setRemoteConnection();
        dPrint(() => endpoint ?? 'failed to set endpoint');
        return endpoint;
      } catch (error, stackTrace) {
        _log.severe("Cannot set remote endpoint", error, stackTrace);
      }

      // If everything failed, fall back to the previously used endpoint (if any)
      if (endpoint == null && previousEndpoint != null && previousEndpoint.isNotEmpty) {
        dPrint(() => 'Falling back to previous endpoint: $previousEndpoint');
        await resolveAndSetEndpoint(previousEndpoint);
        endpoint = previousEndpoint;
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

  /// Attempts to connect to the local endpoint.
  /// Returns the endpoint URL if successful, null otherwise.
  Future<String?> tryLocalEndpoint(String? endpoints) async {
    try {
      final localEndpoint = endpoints ?? _getLocalEndpoint();
      if (localEndpoint == null || localEndpoint.isEmpty) {
        _log.fine("Local endpoint is not set");
        return null;
      }

      await resolveAndSetEndpoint(localEndpoint);
      return localEndpoint;
    } catch (error, stackTrace) {
      _log.severe("Cannot set local endpoint", error, stackTrace);
    }

    return null;
  }

  /// Attempts to connect to remote endpoints from the external endpoint list.
  /// Returns the first successful endpoint URL, or null if all fail.
  Future<String?> tryRemoteEndpoints() async {
    List<AuxilaryEndpoint> endpointList;

    try {
      endpointList = getExternalEndpointList();
    } catch (error, stackTrace) {
      _log.severe("Cannot get external endpoint", error, stackTrace);
      return null;
    }

    for (final endpoint in endpointList) {
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

  Future<String?> _setLocalConnection({String? endpoint}) async {
    return await tryLocalEndpoint(endpoint);
  }

  Future<String?> _setRemoteConnection() async {
    return await tryRemoteEndpoints();
  }

  String? _getLocalEndpoint() {
    return Store.tryGet(StoreKey.localEndpoint);
  }

  /// Gets the list of external endpoints from storage.
  /// Returns an empty list if none are configured.
  List<AuxilaryEndpoint> getExternalEndpointList() {
    final jsonString = Store.tryGet(StoreKey.externalEndpointList);

    if (jsonString == null) {
      return [];
    }

    final List<dynamic> jsonList = jsonDecode(jsonString);
    final endpointList = jsonList.map((e) => AuxilaryEndpoint.fromJson(e)).toList();

    return endpointList;
  }

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
    final endpoint = await resolveEndpoint(serverUrl);
    setEndpoint(endpoint);

    // Save in local database for next startup
    Store.put(StoreKey.serverEndpoint, endpoint);
    return endpoint;
  }

  /// Takes a server URL and attempts to resolve the API endpoint.
  ///
  /// Input: [schema://]host[:port][/path]
  ///  schema - optional (default: https)
  ///  host   - required
  ///  port   - optional (default: based on schema)
  ///  path   - optional
  Future<String> resolveEndpoint(String serverUrl) async {
    String url = sanitizeUrl(serverUrl);

    // Check for /.well-known/immich
    final wellKnownEndpoint = await _getWellKnownEndpoint(url);
    if (wellKnownEndpoint.isNotEmpty) {
      url = sanitizeUrl(wellKnownEndpoint);
    }

    if (!await _isEndpointAvailable(url)) {
      throw ApiException(503, "Server is not reachable");
    }

    // Otherwise, assume the URL provided is the api endpoint
    return url;
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

      await tempServerApi.pingServer().timeout(const Duration(seconds: 5));
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
  Future<String> _getWellKnownEndpoint(String baseUrl) async {
    return baseUrl.endsWith('/photos') ? "$baseUrl/api" : "$baseUrl/photos/api";
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
