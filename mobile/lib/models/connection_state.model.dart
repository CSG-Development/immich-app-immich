enum ConnectionStatus {
  connected,
  disconnected,
  reconnecting,
}

enum ConnectionType {
  websocket,
  api,
}

class ConnectionState {
  final ConnectionStatus status;
  final String? lastErrorUrl;
  final DateTime? lastErrorTime;
  final ConnectionType? connectionType;

  const ConnectionState({
    this.status = ConnectionStatus.connected,
    this.lastErrorUrl,
    this.lastErrorTime,
    this.connectionType,
  });

  ConnectionState copyWith({
    ConnectionStatus? status,
    String? lastErrorUrl,
    DateTime? lastErrorTime,
    ConnectionType? connectionType,
  }) {
    return ConnectionState(
      status: status ?? this.status,
      lastErrorUrl: lastErrorUrl ?? this.lastErrorUrl,
      lastErrorTime: lastErrorTime ?? this.lastErrorTime,
      connectionType: connectionType ?? this.connectionType,
    );
  }

  bool get isConnected => status == ConnectionStatus.connected;
  bool get isDisconnected => status == ConnectionStatus.disconnected;
  bool get isReconnecting => status == ConnectionStatus.reconnecting;
  bool get isWebsocketError => connectionType == ConnectionType.websocket;
  bool get isApiError => connectionType == ConnectionType.api;

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is ConnectionState &&
        other.status == status &&
        other.lastErrorUrl == lastErrorUrl &&
        other.lastErrorTime == lastErrorTime &&
        other.connectionType == connectionType;
  }

  @override
  int get hashCode => Object.hash(status, lastErrorUrl, lastErrorTime, connectionType);
}
