//   Do NOT modify or remove this copyright and confidentiality notice
//
//   Copyright (c) 2026 Seagate Technology LLC or one of its affiliates.
//
//   This code is classified as SEAGATE CONFIDENTIAL
//   and may be covered under one or more Non-Disclosure Agreements.
//

import 'package:hc_device/api/remote_access.swagger.dart';
import 'package:hc_device/device_item.dart';

String devicePathDedupKey(DevicePath path) =>
    '${path.type.value}|${path.address}|${path.port}';

List<DevicePath>? dedupeDevicePathList(List<DevicePath>? paths) {
  if (paths == null || paths.isEmpty) {
    return null;
  }

  final unique = <String, DevicePath>{};
  for (final path in paths) {
    unique.putIfAbsent(devicePathDedupKey(path), () => path);
  }
  return unique.values.toList();
}

bool areDevicePathsEquivalent(DevicePaths a, DevicePaths b) {
  if (a.seagateDeviceID != b.seagateDeviceID) {
    return false;
  }

  final left =
      dedupeDevicePathList(a.paths)?.map(devicePathDedupKey).toSet() ?? <String>{};
  final right =
      dedupeDevicePathList(b.paths)?.map(devicePathDedupKey).toSet() ?? <String>{};
  return left.length == right.length && left.containsAll(right);
}

List<DeviceItem> mergeDiscoveredDevices(
  List<DeviceItem> existing,
  List<DeviceItem> incoming,
) {
  final merged = <String, DeviceItem>{};

  void addDevice(DeviceItem device) {
    final key = device.id;
    final prev = merged[key];
    if (prev == null) {
      merged[key] = DeviceItem(
        hostname: device.hostname,
        baseUrl: device.baseUrl,
        about: device.about,
        status: device.status,
        remoteDevice: device.remoteDevice,
        debugHostType: device.debugHostType,
      );
      return;
    }
    final combined = DeviceItem(
      hostname: prev.hostname ?? device.hostname,
      baseUrl: prev.baseUrl ?? device.baseUrl,
      about: prev.about ?? device.about,
      status: prev.status ?? device.status,
      remoteDevice: prev.remoteDevice ?? device.remoteDevice,
      debugHostType: prev.debugHostType ?? device.debugHostType,
    );
    combined.update(
      baseUrl: device.baseUrl,
      about: device.about,
      status: device.status,
      remoteDevice: device.remoteDevice,
      debugHostType: device.debugHostType,
    );
    merged[key] = combined;
  }

  for (final device in existing) {
    addDevice(device);
  }
  for (final device in incoming) {
    addDevice(device);
  }

  return merged.values.toList();
}
