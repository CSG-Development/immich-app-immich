import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/network.repository.dart';
import 'package:immich_mobile/models/connection_state.model.dart';
import 'package:immich_mobile/models/server_info/server_version.model.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/infrastructure/settings.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/utils/debounce.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';
import 'package:socket_io_client/socket_io_client.dart';

class WebsocketState {
  final Socket? socket;
  final bool isConnected;

  const WebsocketState({this.socket, required this.isConnected});

  WebsocketState copyWith({Socket? socket, bool? isConnected}) {
    return WebsocketState(socket: socket ?? this.socket, isConnected: isConnected ?? this.isConnected);
  }

  @override
  String toString() => 'WebsocketState(socket: $socket, isConnected: $isConnected)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) {
      return true;
    }

    return other is WebsocketState && other.socket == socket && other.isConnected == isConnected;
  }

  @override
  int get hashCode => socket.hashCode ^ isConnected.hashCode;
}

class WebsocketNotifier extends StateNotifier<WebsocketState> {
  WebsocketNotifier(this._ref) : super(const WebsocketState(socket: null, isConnected: false));

  final _log = Logger('WebsocketNotifier');
  final Ref _ref;

  final Debouncer _batchDebouncer = Debouncer(
    interval: const Duration(seconds: 5),
    maxWaitTime: const Duration(seconds: 10),
  );
  final List<dynamic> _batchedAssetUploadReady = [];
  bool _isDisposing = false;

  bool _isWebSocketUnauthorized(dynamic error) {
    final message = error?.toString().toLowerCase() ?? '';
    return message.contains('unauthorized');
  }

  bool _isWebSocketTransportError(dynamic error) {
    final message = error?.toString().toLowerCase() ?? '';
    return message.contains('certificate_verify_failed') || message.contains('handshakeexception');
  }

  void _notifyEndpointRecovery({dynamic error}) {
    if (_isWebSocketUnauthorized(error)) {
      _log.warning('WebSocket unauthorized; skipping endpoint recovery reconnect');
      return;
    }

    if (_isWebSocketTransportError(error)) {
      _log.warning('WebSocket transport error; skipping endpoint path re-resolution');
      return;
    }

    try {
      final serverEndpoint = Store.tryGet(StoreKey.serverEndpoint);
      if (serverEndpoint == null || serverEndpoint.isEmpty) {
        return;
      }

      final apiService = _ref.read(apiServiceProvider);

      apiService.notifyConnectionState(
        ConnectionState(
          status: ConnectionStatus.reconnecting,
          lastErrorUrl: serverEndpoint,
          lastErrorTime: DateTime.now(),
          connectionType: ConnectionType.websocket,
        ),
      );

      apiService.curatorNetworkForceReconnectHandler?.call();
    } catch (error, stackTrace) {
      _log.warning("Failed to notify endpoint recovery service (non-critical)", error, stackTrace);
    }
  }

  @override
  void dispose() {
    disposeSocket();
    _batchDebouncer.dispose();
    super.dispose();
  }

  Future<void> disposeSocket() async {
    if (_isDisposing) {
      return;
    }
    _isDisposing = true;

    try {
      final socket = state.socket;
      if (socket != null) {
        socket
          ..off('AssetUploadReadyV1')
          ..off('AssetEditReadyV1')
          ..off('on_config_update')
          ..off('on_new_release')
          ..off('error')
          ..off('connect_error')
          ..off('connect_timeout')
          ..off('reconnect_error')
          ..off('reconnect_failed')
          ..off('disconnect')
          ..off('connect');

        socket.disconnect();

        await Future.delayed(const Duration(milliseconds: 150));

        try {
          socket.dispose();
        } catch (_) {}
      }
    } catch (_) {}

    state = const WebsocketState(isConnected: false, socket: null);
    _isDisposing = false;
  }

  Future<void> connect({bool force = false}) async {
    if (state.isConnected && !force) {
      return;
    }

    if (force && state.socket != null) {
      dPrint(() => 'Force reconnect: disposing existing socket first');
      await disposeSocket();
    }

    _doConnect();
  }

  void _doConnect() {
    final authenticationState = _ref.read(authProvider);

    final apiService = _ref.read(apiServiceProvider);
    final accessToken = apiService.transientAccessToken ?? Store.tryGet(StoreKey.accessToken);
    if (authenticationState.isAuthenticated && accessToken != null && accessToken.isNotEmpty) {
      try {
        final serverEndpoint = Store.tryGet(StoreKey.serverEndpoint);
        if (serverEndpoint == null || serverEndpoint.isEmpty) {
          _log.warning('Cannot connect websocket: Server endpoint is empty');
          return;
        }

        if (state.socket != null && !_isDisposing) {
          _log.warning('Socket already exists, will be disposed by force reconnect');
          return;
        }

        final endpoint = Uri.parse(serverEndpoint);
        dPrint(() => 'Creating websocket connection to: ${endpoint.origin}${endpoint.path}');
        final headers = ApiService.getAuthenticatedRequestHeaders();
        if (!headers.containsKey('Authorization')) {
          headers['Authorization'] = 'Bearer $accessToken';
        }
        if (endpoint.userInfo.isNotEmpty) {
          headers["Authorization"] = "Basic ${base64.encode(utf8.encode(endpoint.userInfo))}";
        }

        dPrint(() => "Attempting to connect to websocket at ${endpoint.origin}${endpoint.path}/socket.io");
        final options = OptionBuilder()
            .setPath("${endpoint.path}/socket.io")
            .setTransports(['websocket'])
            .disableReconnection()
            .enableForceNew()
            .enableForceNewConnection()
            .disableAutoConnect()
            .setExtraHeaders(headers);

        if (Platform.isIOS || Platform.isAndroid) {
          options.setWebSocketConnector(
            (uri, {protocols, headers}) => NetworkRepository.createWebSocket(
              uri,
              protocols: protocols,
              headers: headers,
            ),
          );
        }

        Socket socket = io(endpoint.origin, options.build());

        socket.onConnect((_) {
          dPrint(() => "Established Websocket Connection");
          state = WebsocketState(isConnected: true, socket: socket);
          _ref.read(apiServiceProvider).notifyConnectionState(
            const ConnectionState(
              status: ConnectionStatus.connected,
              connectionType: ConnectionType.websocket,
            ),
          );
        });

        socket.onDisconnect((_) {
          dPrint(() => "Disconnect to Websocket Connection");
          state = const WebsocketState(isConnected: false, socket: null);
        });

        socket.on('error', (errorMessage) {
          _log.severe("Websocket Error - $errorMessage");
          state = const WebsocketState(isConnected: false, socket: null);
          if (!_isWebSocketUnauthorized(errorMessage)) {
            _notifyEndpointRecovery(error: errorMessage);
          }
          disposeSocket();
        });

        socket.on('connect_error', (data) {
          _log.severe("Websocket connect_error - $data");
          state = const WebsocketState(isConnected: false, socket: null);
          if (!_isWebSocketUnauthorized(data)) {
            _notifyEndpointRecovery(error: data);
          }
          disposeSocket();
        });

        socket.on('connect_timeout', (data) {
          _log.severe("Websocket connect_timeout - $data");
          state = const WebsocketState(isConnected: false, socket: null);
          _notifyEndpointRecovery(error: data);
          disposeSocket();
        });

        socket.on('AssetUploadReadyV1', _handleSyncAssetUploadReadyV1);
        socket.on('AssetUploadReadyV2', _handleSyncAssetUploadReadyV2);
        socket.on('AssetEditReadyV1', _handleSyncAssetEditReadyV1);
        socket.on('AssetEditReadyV2', _handleSyncAssetEditReadyV2);
        socket.on('on_album_update', _handleAlbumUpdate);
        socket.on('on_config_update', _handleOnConfigUpdate);
        socket.on('on_new_release', _handleReleaseUpdates);

        state = WebsocketState(isConnected: false, socket: socket);

        socket.connect();
      } catch (e) {
        dPrint(() => "[WEBSOCKET] Catch Websocket Error - ${e.toString()}");
      }
    }
  }

  void disconnect() {
    dPrint(() => "Attempting to disconnect from websocket");

    _batchedAssetUploadReady.clear();

    state.socket?.dispose();
    state = const WebsocketState(isConnected: false, socket: null);
  }

  Future<void> waitForEvent(String event, bool Function(dynamic)? predicate, Duration timeout) {
    final completer = Completer<void>();

    void handler(dynamic data) {
      if (predicate == null || predicate(data)) {
        completer.complete();
        state.socket?.off(event, handler);
      }
    }

    state.socket?.on(event, handler);

    return completer.future.timeout(
      timeout,
      onTimeout: () {
        state.socket?.off(event, handler);
        completer.completeError(TimeoutException("Timeout waiting for event: $event"));
      },
    );
  }

  void _handleOnConfigUpdate(dynamic _) {
    _ref.read(serverInfoProvider.notifier).getServerFeatures();
    _ref.read(serverInfoProvider.notifier).getServerConfig();
  }

  _handleReleaseUpdates(dynamic data) {
    if (data is! Map) {
      return;
    }

    final json = data.cast<String, dynamic>();
    final serverVersionJson = json.containsKey('serverVersion') ? json['serverVersion'] : null;
    final releaseVersionJson = json.containsKey('releaseVersion') ? json['releaseVersion'] : null;
    if (serverVersionJson == null || releaseVersionJson == null) {
      return;
    }

    final serverVersionDto = ServerVersionResponseDto.fromJson(serverVersionJson);
    final releaseVersionDto = ServerVersionResponseDto.fromJson(releaseVersionJson);
    if (serverVersionDto == null || releaseVersionDto == null) {
      return;
    }

    final serverVersion = ServerVersion.fromDto(serverVersionDto);
    final releaseVersion = ServerVersion.fromDto(releaseVersionDto);
    _ref.read(serverInfoProvider.notifier).handleReleaseInfo(serverVersion, releaseVersion);
  }

  void _handleSyncAssetUploadReadyV1(dynamic data) {
    _batchedAssetUploadReady.add(data);
    _batchDebouncer.run(_processBatchedAssetUploadReadyV1);
  }

  void _handleSyncAssetUploadReadyV2(dynamic data) {
    _batchedAssetUploadReady.add(data);
    _batchDebouncer.run(_processBatchedAssetUploadReadyV2);
  }

  void _handleSyncAssetEditReadyV1(dynamic data) {
    unawaited(_ref.read(backgroundSyncProvider).syncWebsocketEditV1(data));
  }

  void _handleAlbumUpdate(dynamic _) {
    unawaited(_ref.read(backgroundSyncProvider).syncRemote());
  }

  void _handleSyncAssetEditReadyV2(dynamic data) {
    unawaited(_ref.read(backgroundSyncProvider).syncWebsocketEditV2(data));
  }

  void _processBatchedAssetUploadReadyV1() {
    if (_batchedAssetUploadReady.isEmpty) {
      return;
    }

    final isSyncAlbumEnabled = _ref.read(appConfigProvider).backup.syncAlbums;
    try {
      unawaited(
        _ref.read(backgroundSyncProvider).syncWebsocketBatchV1(_batchedAssetUploadReady.toList()).then((_) {
          if (isSyncAlbumEnabled) {
            _ref.read(backgroundSyncProvider).syncLinkedAlbum();
          }
        }),
      );
    } catch (error) {
      _log.severe("Error processing batched AssetUploadReadyV1 events: $error");
    }

    _batchedAssetUploadReady.clear();
  }

  void _processBatchedAssetUploadReadyV2() {
    if (_batchedAssetUploadReady.isEmpty) {
      return;
    }

    final isSyncAlbumEnabled = _ref.read(appConfigProvider).backup.syncAlbums;
    try {
      unawaited(
        _ref.read(backgroundSyncProvider).syncWebsocketBatchV2(_batchedAssetUploadReady.toList()).then((_) {
          if (isSyncAlbumEnabled) {
            _ref.read(backgroundSyncProvider).syncLinkedAlbum();
          }
        }),
      );
    } catch (error) {
      _log.severe("Error processing batched AssetUploadReadyV2 events: $error");
    }

    _batchedAssetUploadReady.clear();
  }
}

final websocketProvider = StateNotifierProvider<WebsocketNotifier, WebsocketState>((ref) {
  return WebsocketNotifier(ref);
});
