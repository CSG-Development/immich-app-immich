import 'dart:async';
import 'dart:convert';

import 'package:collection/collection.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/server_info/server_version.model.dart';
import 'package:immich_mobile/models/connection_state.model.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/asset.provider.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/background_sync.provider.dart';
import 'package:immich_mobile/providers/db.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/services/sync.service.dart';
import 'package:immich_mobile/utils/debounce.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';
import 'package:socket_io_client/socket_io_client.dart';

enum PendingAction { assetDelete, assetUploaded, assetHidden, assetTrash }

class PendingChange {
  final String id;
  final PendingAction action;
  final dynamic value;

  const PendingChange(this.id, this.action, this.value);

  @override
  String toString() => 'PendingChange(id: $id, action: $action, value: $value)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is PendingChange && other.id == id && other.action == action;
  }

  @override
  int get hashCode => id.hashCode ^ action.hashCode;
}

class WebsocketState {
  final Socket? socket;
  final bool isConnected;
  final List<PendingChange> pendingChanges;

  const WebsocketState({this.socket, required this.isConnected, required this.pendingChanges});

  WebsocketState copyWith({Socket? socket, bool? isConnected, List<PendingChange>? pendingChanges}) {
    return WebsocketState(
      socket: socket ?? this.socket,
      isConnected: isConnected ?? this.isConnected,
      pendingChanges: pendingChanges ?? this.pendingChanges,
    );
  }

  @override
  String toString() => 'WebsocketState(socket: $socket, isConnected: $isConnected)';

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;

    return other is WebsocketState && other.socket == socket && other.isConnected == isConnected;
  }

  @override
  int get hashCode => socket.hashCode ^ isConnected.hashCode;
}

class WebsocketNotifier extends StateNotifier<WebsocketState> {
  WebsocketNotifier(this._ref)
      : super(const WebsocketState(socket: null, isConnected: false, pendingChanges: []));

  final _log = Logger('WebsocketNotifier');
  final Ref _ref;
  final Debouncer _debounce = Debouncer(interval: const Duration(milliseconds: 500));

  final Debouncer _batchDebouncer = Debouncer(
    interval: const Duration(seconds: 5),
    maxWaitTime: const Duration(seconds: 10),
  );
  final List<dynamic> _batchedAssetUploadReady = [];
  bool _isDisposing = false;

  /// Notifies the endpoint recovery service about websocket connection errors
  void _notifyEndpointRecovery() {
    try {
      final serverEndpoint = Store.get(StoreKey.serverEndpoint);
      final apiService = _ref.read(apiServiceProvider);
      
      apiService.notifyConnectionState(ConnectionState(
        status: ConnectionStatus.reconnecting,
        lastErrorUrl: serverEndpoint.isNotEmpty ? serverEndpoint : null,
        lastErrorTime: DateTime.now(),
        connectionType: ConnectionType.websocket,
      ));
    } catch (error, stackTrace) {
      _log.warning("Failed to notify endpoint recovery service (non-critical)", error, stackTrace);
    }
  }

  @override
  void dispose() {
    // Note: disposeSocket is async but we can't await in dispose()
    // Fire and forget - cleanup doesn't need to complete synchronously
    disposeSocket();
    _batchDebouncer.dispose();
    super.dispose();
  }

  Future<void> disposeSocket() async {
    if (_isDisposing) return; // Prevent concurrent disposal
    _isDisposing = true;
    
    try {
      final socket = state.socket;
      if (socket != null) {
        // Remove all listeners for known events before disposing.
        socket
          ..off('on_upload_success')
          ..off('on_asset_delete')
          ..off('on_asset_trash')
          ..off('on_asset_restore')
          ..off('on_asset_update')
          ..off('on_asset_stack_update')
          ..off('on_asset_hidden')
          ..off('AssetUploadReadyV1')
          ..off('on_config_update')
          ..off('on_new_release')
          ..off('error')
          ..off('connect_error')
          ..off('connect_timeout')
          ..off('reconnect_error')
          ..off('reconnect_failed')
          ..off('disconnect')
          ..off('connect');
        
        // Disconnect and dispose
        socket.disconnect();
        
        // Wait a bit to ensure disconnect completes and reconnection attempts stop
        await Future.delayed(const Duration(milliseconds: 150));
        
        try {
          socket.dispose();
        } catch (_) {
          // Ignore disposal errors
        }
      }
    } catch (_) {
      // Best-effort cleanup; ignore any errors from socket disposal.
    }
    
    state = WebsocketState(isConnected: false, socket: null, pendingChanges: state.pendingChanges);
    _isDisposing = false;
  }

  /// Connects websocket to server unless already connected, or if [force] is true.
  Future<void> connect({bool force = false}) async {
    if (state.isConnected && !force) return;
    
    // If forcing a reconnection, dispose any existing socket first to prevent
    // old socket reconnection attempts from interfering with the new connection.
    if (force && state.socket != null) {
      dPrint(() => 'Force reconnect: disposing existing socket first');
      await disposeSocket();
    }
    
    _doConnect();
  }

  void _doConnect() {
    final authenticationState = _ref.read(authProvider);

    if (authenticationState.isAuthenticated) {
      try {
        // Use the full server endpoint URL from Store (updated by ApiService.setEndpoint)
        // instead of apiClient.basePath which is just the relative path component.
        final serverEndpoint = Store.get(StoreKey.serverEndpoint);
        if (serverEndpoint.isEmpty) {
          _log.warning('Cannot connect websocket: Server endpoint is empty');
          return;
        }

        // Double-check we don't have an old socket still active
        if (state.socket != null && !_isDisposing) {
          _log.warning('Socket already exists, will be disposed by force reconnect');
          return;
        }

        final endpoint = Uri.parse(serverEndpoint);
        dPrint(() => 'Creating websocket connection to: ${endpoint.origin}${endpoint.path}');
        final headers = ApiService.getRequestHeaders();
        if (endpoint.userInfo.isNotEmpty) {
          headers["Authorization"] = "Basic ${base64.encode(utf8.encode(endpoint.userInfo))}";
        }

        dPrint(() => "Attempting to connect to websocket at ${endpoint.origin}${endpoint.path}/socket.io");
        // Configure socket transports must be specified
        // Disable auto-connect to prevent duplicate event handlers and have manual control
        Socket socket = io(
          endpoint.origin,
          OptionBuilder()
              .setPath("${endpoint.path}/socket.io")
              .setTransports(['websocket'])
              .disableReconnection()
              .enableForceNew()
              .enableForceNewConnection()
              .disableAutoConnect()
              .setExtraHeaders(headers)
              .build(),
        );

        socket.onConnect((_) {
          dPrint(() => "Established Websocket Connection");
          state = WebsocketState(isConnected: true, socket: socket, pendingChanges: state.pendingChanges);
        });

        socket.onDisconnect((_) {
          dPrint(() => "Disconnect to Websocket Connection");
          state = WebsocketState(isConnected: false, socket: null, pendingChanges: state.pendingChanges);
        });

        socket.on('error', (errorMessage) {
          _log.severe("Websocket Error - $errorMessage");
          // Update state immediately to reflect connection failure
          state = WebsocketState(isConnected: false, socket: null, pendingChanges: state.pendingChanges);
          // Notify endpoint recovery service to attempt recovery
          _notifyEndpointRecovery();
          // Dispose socket to clean up resources and stop any reconnection attempts
          disposeSocket();
        });

        socket.on('connect_error', (data) {
          _log.severe("Websocket connect_error - $data");
          // Update state immediately to reflect connection failure
          state = WebsocketState(isConnected: false, socket: null, pendingChanges: state.pendingChanges);
          // Notify endpoint recovery service to attempt recovery
          _notifyEndpointRecovery();
          // Dispose socket to stop automatic reconnection attempts
          disposeSocket();
        });

        socket.on('connect_timeout', (data) {
          _log.severe("Websocket connect_timeout - $data");
          // Update state immediately to reflect connection failure
          state = WebsocketState(isConnected: false, socket: null, pendingChanges: state.pendingChanges);
          // Notify endpoint recovery service to attempt recovery
          _notifyEndpointRecovery();
          // Dispose socket to stop automatic reconnection attempts
          disposeSocket();
        });

        if (!Store.isBetaTimelineEnabled) {
          socket.on('on_upload_success', _handleOnUploadSuccess);
          socket.on('on_asset_delete', _handleOnAssetDelete);
          socket.on('on_asset_trash', _handleOnAssetTrash);
          socket.on('on_asset_restore', _handleServerUpdates);
          socket.on('on_asset_update', _handleServerUpdates);
          socket.on('on_asset_stack_update', _handleServerUpdates);
          socket.on('on_asset_hidden', _handleOnAssetHidden);
        } else {
          socket.on('AssetUploadReadyV1', _handleSyncAssetUploadReady);
        }

        socket.on('on_config_update', _handleOnConfigUpdate);
        socket.on('on_new_release', _handleReleaseUpdates);
        
        // Update state with the new socket before connecting
        state = WebsocketState(isConnected: false, socket: socket, pendingChanges: state.pendingChanges);
        
        // Manually connect after all event handlers are registered
        socket.connect();
      } catch (e) {
        dPrint(() => "[WEBSOCKET] Catch Websocket Error - ${e.toString()}");
      }
    }
  }

  void disconnect() {
    dPrint(() => "Attempting to disconnect from websocket");

    _batchedAssetUploadReady.clear();

    var socket = state.socket?.disconnect();

    if (socket?.disconnected == true) {
      state = WebsocketState(isConnected: false, socket: null, pendingChanges: state.pendingChanges);
    }
  }

  void stopListenToEvent(String eventName) {
    state.socket?.off(eventName);
  }

  void stopListenToOldEvents() {
    state.socket?.off('on_upload_success');
    state.socket?.off('on_asset_delete');
    state.socket?.off('on_asset_trash');
    state.socket?.off('on_asset_restore');
    state.socket?.off('on_asset_update');
    state.socket?.off('on_asset_stack_update');
    state.socket?.off('on_asset_hidden');
  }

  void startListeningToOldEvents() {
    state.socket?.on('on_upload_success', _handleOnUploadSuccess);
    state.socket?.on('on_asset_delete', _handleOnAssetDelete);
    state.socket?.on('on_asset_trash', _handleOnAssetTrash);
    state.socket?.on('on_asset_restore', _handleServerUpdates);
    state.socket?.on('on_asset_update', _handleServerUpdates);
    state.socket?.on('on_asset_stack_update', _handleServerUpdates);
    state.socket?.on('on_asset_hidden', _handleOnAssetHidden);
  }

  void stopListeningToBetaEvents() {
    state.socket?.off('AssetUploadReadyV1');
  }

  void startListeningToBetaEvents() {
    state.socket?.on('AssetUploadReadyV1', _handleSyncAssetUploadReady);
  }

  void listenUploadEvent() {
    dPrint(() => "Start listening to event on_upload_success");
    state.socket?.on('on_upload_success', _handleOnUploadSuccess);
  }

  void addPendingChange(PendingAction action, dynamic value) {
    final now = DateTime.now();
    state = state.copyWith(
      pendingChanges: [...state.pendingChanges, PendingChange(now.millisecondsSinceEpoch.toString(), action, value)],
    );
    _debounce.run(handlePendingChanges);
  }

  Future<void> _handlePendingTrashes() async {
    final trashChanges = state.pendingChanges.where((c) => c.action == PendingAction.assetTrash).toList();
    if (trashChanges.isNotEmpty) {
      List<String> remoteIds = trashChanges.expand((a) => (a.value as List).map((e) => e.toString())).toList();

      await _ref.read(syncServiceProvider).handleRemoteAssetRemoval(remoteIds);
      await _ref.read(assetProvider.notifier).getAllAsset();

      state = state.copyWith(pendingChanges: state.pendingChanges.whereNot((c) => trashChanges.contains(c)).toList());
    }
  }

  Future<void> _handlePendingDeletes() async {
    final deleteChanges = state.pendingChanges.where((c) => c.action == PendingAction.assetDelete).toList();
    if (deleteChanges.isNotEmpty) {
      List<String> remoteIds = deleteChanges.map((a) => a.value.toString()).toList();
      await _ref.read(syncServiceProvider).handleRemoteAssetRemoval(remoteIds);
      state = state.copyWith(pendingChanges: state.pendingChanges.whereNot((c) => deleteChanges.contains(c)).toList());
    }
  }

  Future<void> _handlePendingUploaded() async {
    final uploadedChanges = state.pendingChanges.where((c) => c.action == PendingAction.assetUploaded).toList();
    if (uploadedChanges.isNotEmpty) {
      List<AssetResponseDto?> remoteAssets = uploadedChanges.map((a) => AssetResponseDto.fromJson(a.value)).toList();
      for (final dto in remoteAssets) {
        if (dto != null) {
          final newAsset = Asset.remote(dto);
          await _ref.watch(assetProvider.notifier).onNewAssetUploaded(newAsset);
        }
      }
      state = state.copyWith(
        pendingChanges: state.pendingChanges.whereNot((c) => uploadedChanges.contains(c)).toList(),
      );
    }
  }

  Future<void> _handlingPendingHidden() async {
    final hiddenChanges = state.pendingChanges.where((c) => c.action == PendingAction.assetHidden).toList();
    if (hiddenChanges.isNotEmpty) {
      List<String> remoteIds = hiddenChanges.map((a) => a.value.toString()).toList();
      final db = _ref.watch(dbProvider);
      await db.writeTxn(() => db.assets.deleteAllByRemoteId(remoteIds));

      state = state.copyWith(pendingChanges: state.pendingChanges.whereNot((c) => hiddenChanges.contains(c)).toList());
    }
  }

  Future<void> handlePendingChanges() async {
    await _handlePendingUploaded();
    await _handlePendingDeletes();
    await _handlingPendingHidden();
    await _handlePendingTrashes();
  }

  void _handleOnConfigUpdate(dynamic _) {
    _ref.read(serverInfoProvider.notifier).getServerFeatures();
    _ref.read(serverInfoProvider.notifier).getServerConfig();
  }

  // Refresh updated assets
  void _handleServerUpdates(dynamic _) {
    _ref.read(assetProvider.notifier).getAllAsset();
  }

  void _handleOnUploadSuccess(dynamic data) => addPendingChange(PendingAction.assetUploaded, data);

  void _handleOnAssetDelete(dynamic data) => addPendingChange(PendingAction.assetDelete, data);

  void _handleOnAssetTrash(dynamic data) {
    addPendingChange(PendingAction.assetTrash, data);
  }

  void _handleOnAssetHidden(dynamic data) => addPendingChange(PendingAction.assetHidden, data);

  _handleReleaseUpdates(dynamic data) {
    // Json guard
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
    _ref.read(serverInfoProvider.notifier).handleNewRelease(serverVersion, releaseVersion);
  }

  void _handleSyncAssetUploadReady(dynamic data) {
    _batchedAssetUploadReady.add(data);
    _batchDebouncer.run(_processBatchedAssetUploadReady);
  }

  void _processBatchedAssetUploadReady() {
    if (_batchedAssetUploadReady.isEmpty) {
      return;
    }

    final isSyncAlbumEnabled = Store.get(StoreKey.syncAlbums, false);
    try {
      unawaited(
        _ref.read(backgroundSyncProvider).syncWebsocketBatch(_batchedAssetUploadReady.toList()).then((_) {
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
}

final websocketProvider = StateNotifierProvider<WebsocketNotifier, WebsocketState>((ref) {
  return WebsocketNotifier(ref);
});
