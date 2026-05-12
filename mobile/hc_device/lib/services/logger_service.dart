//   Do NOT modify or remove this copyright and confidentiality notice
//
//   Copyright (c) 2026 Seagate Technology LLC or one of its affiliates.
//
//   This code is classified as SEAGATE CONFIDENTIAL
//   and may not be used, modified, duplicated, derived, distributed, or disclosed
//   except as expressly authorized.

import 'dart:async';

import 'package:chopper/chopper.dart';
import 'package:flutter/foundation.dart' show kDebugMode;
import 'package:logging/logging.dart';

/// Root logger for `hc_device`.
final Logger hcDeviceLogger = Logger('HcDevice');

/// Optional Chopper interceptor used for detailed HTTP logs.
///
/// Attach to short-lived unauthenticated clients (e.g. [DeviceDetectionService.getAbout]).
final class HcDeviceChopperLogInterceptor implements Interceptor {
  @override
  FutureOr<Response<BodyType>> intercept<BodyType>(Chain<BodyType> chain) async {
    final req = chain.request;
    hcDeviceLogger.fine('[HC-HTTP] --> ${req.method} ${req.url}');
    try {
      final res = await chain.proceed(req);
      hcDeviceLogger.fine('[HC-HTTP] <-- ${res.statusCode} ${req.url}');
      return res;
    } catch (e, st) {
      hcDeviceLogger.fine('[HC-HTTP] xx ${req.method} ${req.url}', e, st);
      rethrow;
    }
  }
}

/// Interceptors suitable for [Api.create] on probe / discovery clients.
List<Interceptor> hcDeviceHttpLogInterceptors() => [
      if (kDebugMode) HcDeviceChopperLogInterceptor(),
    ];

final Interceptor httpLogger = HcDeviceChopperLogInterceptor();

final class HcDeviceReferenceLogger {
  void debug(String message, [Object? error]) {
    if (error != null) {
      hcDeviceLogger.fine(message, error);
    } else {
      hcDeviceLogger.fine(message);
    }
  }

  void info(String message) => hcDeviceLogger.info(message);

  void warning(String message, [Object? error, StackTrace? stackTrace]) {
    if (error != null) {
      hcDeviceLogger.warning(message, error, stackTrace);
    } else {
      hcDeviceLogger.warning(message);
    }
  }

  void error(String message, [Object? error, StackTrace? stackTrace]) {
    if (error != null) {
      hcDeviceLogger.severe(message, error, stackTrace);
    } else {
      hcDeviceLogger.severe(message);
    }
  }

  void verbose(String message) => hcDeviceLogger.finer(message);
}

/// Global logger used across hc_device services (for example, device detection).
final HcDeviceReferenceLogger logger = HcDeviceReferenceLogger();
