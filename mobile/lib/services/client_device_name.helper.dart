import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:logging/logging.dart';

/// Helper for resolving a human‑readable name for the current device.
///
/// The value is cached for the process lifetime to avoid repeated calls
/// to `DeviceInfoPlugin`.
class ClientDeviceNameHelper {
  static final Logger _log = Logger('ClientDeviceNameHelper');
  static String? _cachedClientFriendlyName;

  static Future<String> getClientFriendlyName() async {
    if (_cachedClientFriendlyName != null && _cachedClientFriendlyName!.isNotEmpty) {
      return _cachedClientFriendlyName!;
    }

    final deviceInfo = DeviceInfoPlugin();
    String name = 'Personal Cloud Photos';

    try {
      if (Platform.isAndroid) {
        final androidInfo = await deviceInfo.androidInfo;
        if (androidInfo.name.isNotEmpty) {
          name = androidInfo.name;
        } else if (androidInfo.brand.isNotEmpty) {
          // Fallback to "Brand Model"
          name = '${androidInfo.brand} ${androidInfo.model}';
        } else {
          name = androidInfo.model;
        }
      } else if (Platform.isIOS) {
        final iosInfo = await deviceInfo.iosInfo;
        if (iosInfo.modelName.isNotEmpty) {
          name = iosInfo.modelName;
        } else if (iosInfo.name.isNotEmpty) {
          name = iosInfo.name;
        }
      }
    } catch (error, stackTrace) {
      _log.warning('Failed to resolve client friendly name for remote access', error, stackTrace);
    }

    if (kDebugMode) {
      debugPrint('ClientDeviceNameHelper.getClientFriendlyName => $name');
    }

    _cachedClientFriendlyName = name;
    return name;
  }
}

