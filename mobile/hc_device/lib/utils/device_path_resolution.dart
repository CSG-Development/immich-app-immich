//   Do NOT modify or remove this copyright and confidentiality notice
//
//   Copyright (c) 2026 Seagate Technology LLC or one of its affiliates.
//
//   This code is classified as SEAGATE CONFIDENTIAL
//   and may be covered under one or more Non-Disclosure Agreements.
//

import 'dart:async';

import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:hc_device/api/remote_access.enums.swagger.dart' show DevicePathType;
import 'package:hc_device/api/remote_access.swagger.dart' show DevicePath;

typedef PathProbe<T> = Future<T?> Function(DevicePath path);

Future<bool> checkWiFiConnectivityWithFallback({
  required Future<List<ConnectivityResult>> Function() connectivityChecker,
  void Function()? onNoWifi,
  void Function(Object error)? onError,
}) async {
  try {
    final connectivityResults = await connectivityChecker();
    final hasWiFi = connectivityResults.contains(ConnectivityResult.wifi);
    if (!hasWiFi) {
      onNoWifi?.call();
    }
    return hasWiFi;
  } catch (error) {
    onError?.call(error);
    return true;
  }
}

Future<T?> resolvePriorityPathInOrder<T>({
  required List<DevicePath> paths,
  required PathProbe<T> probePath,
}) async {
  if (paths.isEmpty) {
    return null;
  }

  final completer = Completer<T?>();
  var pendingCount = paths.length;
  var localPendingCount = paths.where((path) => path.type == DevicePathType.local).length;
  T? publicResult;

  Future<void> finalizePath(DevicePath path, T? result) async {
    if (result != null && !completer.isCompleted) {
      if (path.type == DevicePathType.local) {
        completer.complete(result);
      } else if (path.type == DevicePathType.public) {
        publicResult ??= result;
      }
    }

    if (path.type == DevicePathType.local) {
      localPendingCount--;
      if (localPendingCount == 0 && publicResult != null && !completer.isCompleted) {
        completer.complete(publicResult);
      }
    }

    pendingCount--;
    if (pendingCount == 0 && !completer.isCompleted) {
      completer.complete(publicResult);
    }
  }

  for (final path in paths) {
    probePath(path)
        .then((result) => finalizePath(path, result))
        .catchError((_) => finalizePath(path, null));
  }

  return completer.future;
}

Future<T?> resolveDevicePathWithFallback<T>({
  required List<DevicePath> paths,
  required bool hasWiFi,
  required PathProbe<T> probePath,
  void Function(DevicePath path)? onLocalPathSkipped,
  void Function(DevicePath path)? onRelayFallback,
}) async {
  DevicePath? relayPath;
  final priorityPaths = <DevicePath>[];

  for (final path in paths) {
    switch (path.type) {
      case DevicePathType.local:
        if (hasWiFi) {
          priorityPaths.add(path);
        } else {
          onLocalPathSkipped?.call(path);
        }
        break;
      case DevicePathType.public:
        priorityPaths.add(path);
        break;
      case DevicePathType.remote:
        relayPath ??= path;
        break;
      default:
        break;
    }
  }

  final priorityResult = await resolvePriorityPathInOrder(
    paths: priorityPaths,
    probePath: probePath,
  );
  if (priorityResult != null) {
    return priorityResult;
  }

  if (relayPath != null) {
    onRelayFallback?.call(relayPath);
    return probePath(relayPath);
  }

  return null;
}
