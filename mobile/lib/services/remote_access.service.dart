import 'dart:io';

import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:homecloud_frontend/remote_auth.provider.dart';
import 'package:logging/logging.dart';

/// Centralized helper for remote access (OTP) flows.
///
/// This service is injected with a [RemoteAuthController] and is exposed
/// via a Riverpod provider so widgets and services don't have to deal with
/// the controller directly.
class RemoteAccessService {
  final RemoteAuthController _controller;

  RemoteAccessService(this._controller);

  static final Logger _log = Logger('RemoteAccessService');
  static String? _cachedClientFriendlyName;

  /// Returns a human‑readable name for the current client device.
  ///
  /// The value is cached for the process lifetime to avoid repeated calls
  /// to `DeviceInfoPlugin`.
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
      debugPrint('RemoteAccessService.getClientFriendlyName => $name');
    }

    _cachedClientFriendlyName = name;
    return name;
  }

  /// Initiates remote access (OTP) for the given [email].
  Future<void> initiate(String email) async {
    final clientFriendlyName = await getClientFriendlyName();

    _log.fine('Initiating remote access for email=$email with clientName=$clientFriendlyName');
    await _controller.initiate(
      email: email,
      clientFriendlyName: clientFriendlyName,
    );

    final state = _controller.state;
    if (state.error != null) {
      _log.severe(
        '[RemoteAccessService] initiate error: ${state.error} - ${state.errorMessage}',
      );
    }
  }
}

