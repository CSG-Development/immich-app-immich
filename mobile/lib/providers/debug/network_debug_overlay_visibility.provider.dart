import 'package:hooks_riverpod/hooks_riverpod.dart';

/// Debug-only network overlay; off until unlocked via Settings → Networking title.
final networkDebugOverlayVisibleProvider = StateProvider<bool>((ref) => false);

/// Returns true when the 5th tap within a 2s sliding window completes (buffer is cleared).
bool tryConsumeNetworkDebugOverlaySecretTap(List<DateTime> tapTimesBuffer) {
  final now = DateTime.now();
  tapTimesBuffer.removeWhere((t) => now.difference(t) > const Duration(seconds: 2));
  tapTimesBuffer.add(now);
  if (tapTimesBuffer.length >= 5) {
    tapTimesBuffer.clear();
    return true;
  }
  return false;
}
