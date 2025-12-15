import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/connection_state.model.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:logging/logging.dart';

class ConnectionStateNotifier extends StateNotifier<ConnectionState> {
  ConnectionStateNotifier(this._ref) : super(const ConnectionState()) {
    _initializeConnectionStateListener();
  }

  final Ref _ref;
  final _log = Logger('ConnectionStateNotifier');
  StreamSubscription<ConnectionState>? _connectionStateSubscription;

  void _initializeConnectionStateListener() {
    final apiService = _ref.read(apiServiceProvider);
    _connectionStateSubscription = apiService.connectionStateChanges.listen(
      (newState) {
        state = newState;
      },
      onError: (error, stackTrace) {
        _log.severe('Error in connection state stream', error, stackTrace);
      },
    );
  }

  @override
  void dispose() {
    _connectionStateSubscription?.cancel();
    super.dispose();
  }
}

final connectionStateProvider = StateNotifierProvider<ConnectionStateNotifier, ConnectionState>((ref) {
  return ConnectionStateNotifier(ref);
});
