import 'package:hc_device/api/remote_access.swagger.dart';
import 'package:hc_device/utils/device_merge.dart';

bool shouldRefreshCachedPaths({
  required bool usedCache,
  required bool priorityFailed,
  required bool cacheExpired,
}) {
  return usedCache && priorityFailed && cacheExpired;
}

bool shouldRetryWithFreshPaths(
  DevicePaths cachedPaths,
  DevicePaths freshPaths,
) {
  return !areDevicePathsEquivalent(cachedPaths, freshPaths);
}
