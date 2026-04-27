enum NetworkReconnectBranch { knownSeagateFastPath, fullDiscoveryFallback }

bool shouldIgnoreFirstConnectivityEvent({required bool hasSeenConnectivityEvent}) {
  return !hasSeenConnectivityEvent;
}

NetworkReconnectBranch selectReconnectBranch({
  required String? knownSeagateDeviceID,
  required bool fastPathResolved,
}) {
  if (knownSeagateDeviceID != null &&
      knownSeagateDeviceID.isNotEmpty &&
      !fastPathResolved) {
    return NetworkReconnectBranch.fullDiscoveryFallback;
  }
  if (knownSeagateDeviceID != null && knownSeagateDeviceID.isNotEmpty) {
    return NetworkReconnectBranch.knownSeagateFastPath;
  }
  return NetworkReconnectBranch.fullDiscoveryFallback;
}
