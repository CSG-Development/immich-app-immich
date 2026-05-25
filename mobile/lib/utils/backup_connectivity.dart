import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/services.dart';
import 'package:immich_mobile/extensions/network_capability_extensions.dart';
import 'package:immich_mobile/platform/connectivity_api.g.dart';
import 'package:immich_mobile/services/app_settings.service.dart';
import 'package:logging/logging.dart';

final _log = Logger('BackupConnectivity');

/// Resolves whether backup may treat the network as Wi‑Fi for [requireWifi] assets.
///
/// Prefer native [ConnectivityApi]; fall back to [Connectivity] when the Pigeon
/// channel is not ready (e.g. early after app restart).
Future<bool> resolveBackupHasWifi({ConnectivityApi? connectivityApi}) async {
  if (connectivityApi != null) {
    try {
      final capabilities = await connectivityApi.getCapabilities();
      return capabilities.hasWifi;
    } on PlatformException catch (error, stackTrace) {
    _log.warning(
      'ConnectivityApi unavailable (${error.code}), using connectivity_plus fallback',
      error,
      stackTrace,
    );
    } catch (error, stackTrace) {
      _log.warning('ConnectivityApi failed, using connectivity_plus fallback', error, stackTrace);
    }
  }

  return _hasWifiFromConnectivityPlus();
}

Future<bool> _hasWifiFromConnectivityPlus() async {
  try {
    final results = await Connectivity().checkConnectivity();
    return results.contains(ConnectivityResult.wifi) || results.contains(ConnectivityResult.ethernet);
  } catch (error, stackTrace) {
    _log.warning('connectivity_plus failed, assuming WiFi for backup start', error, stackTrace);
    // Last resort: allow backup to proceed; per-asset requiresWiFi still applies in upload loop.
    return true;
  }
}

/// Returns `true` when backup is enabled, the device is not on Wi‑Fi, and
/// cellular uploads are disabled for both photos and videos.
Future<bool> isBackupNetworkBlocked({
  required AppSettingsService appSettings,
  ConnectivityApi? connectivityApi,
}) async {
  final enableBackup = appSettings.getSetting(AppSettingsEnum.enableBackup);
  if (!enableBackup) {
    return false;
  }

  final hasWifi = await resolveBackupHasWifi(connectivityApi: connectivityApi);
  if (hasWifi) {
    return false;
  }

  final cellularPhotos = appSettings.getSetting(AppSettingsEnum.useCellularForUploadPhotos);
  final cellularVideos = appSettings.getSetting(AppSettingsEnum.useCellularForUploadVideos);
  return !cellularPhotos && !cellularVideos;
}
