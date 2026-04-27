import 'dart:async';

import 'package:hc_device/hc_device.dart';

class DeviceDetection {
  DeviceDetection._();

  static Future<List<DeviceItem>> discoverDevices({
    required DeviceProvider deviceProvider,
    required RemoteProvider remoteProvider,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    final completer = Completer<void>();
    final found = <DeviceItem>[];
    late DeviceDetectionService discovery;
    discovery = DeviceDetectionService(
      deviceProvider: deviceProvider,
      remoteProvider: remoteProvider,
      onDeviceFound: found.add,
      onDetectionComplete: (_) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
      onError: (_, __) {
        if (!completer.isCompleted) {
          completer.complete();
        }
      },
    );

    await discovery.startDetection();
    await awaitOrCancel(
      completer: completer,
      discovery: discovery,
      timeout: timeout,
    );
    return found;
  }

  static Future<void> awaitOrCancel({
    required Completer<void> completer,
    required DeviceDetectionService discovery,
    Duration timeout = const Duration(seconds: 45),
  }) async {
    try {
      await completer.future.timeout(timeout);
    } on TimeoutException {
      await discovery.cancelDetection();
    }
  }

  static DeviceItem? findByConnectedDeviceId({
    required List<DeviceItem> devices,
    required String connectedDeviceId,
  }) {
    for (final device in devices) {
      if (device.about?.certificateCommonName == connectedDeviceId ||
          device.remoteDevice?.certificateCommonName == connectedDeviceId) {
        return device;
      }
    }
    return null;
  }
}
