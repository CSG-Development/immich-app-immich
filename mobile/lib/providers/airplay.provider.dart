import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:immich_mobile/services/airplay.service.dart';

/// Provider to track AirPlay connection state
final airplayProvider = StateNotifierProvider<AirplayNotifier, bool>((ref) {
  return AirplayNotifier();
});

class AirplayNotifier extends StateNotifier<bool> {
  AirplayNotifier() : super(false) {
    _initializeAirPlayListener();
  }

  void _initializeAirPlayListener() {
    // Set up AirPlay connection change listener
    AirplayService.airPlayConnectionChanged((isConnected) {
      state = isConnected;
    });
    
    // Check initial AirPlay status
    AirplayService.isAirPlayConnected().then((isConnected) {
      state = isConnected;
    });
  }

  /// Manually update AirPlay connection state
  void updateConnectionState(bool isConnected) {
    state = isConnected;
  }

  /// Disable AirPlay mode (e.g., when conversion fails)
  void disableAirPlayMode() {
    state = false;
  }
}
