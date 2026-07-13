//   Do NOT modify or remove this copyright and confidentiality notice
//
//   Copyright (c) 2026 Seagate Technology LLC or one of its affiliates.
//
//   This code is classified as SEAGATE CONFIDENTIAL
//   and may be covered under one or more Non-Disclosure Agreements.
//   Any use, modification, duplication, derivation, distribution or disclosure
//   of this code, for any reason, not expressly authorized is prohibited.
//   All other rights are expressly reserved by Seagate Technology LLC.
//

import 'package:hc_device/api/api.enums.swagger.dart' as api_enums;
import 'package:hc_device/api/api.swagger.dart' show About, Status;
import 'package:hc_device/api/remote_access.enums.swagger.dart' show DevicePathType;
import 'package:hc_device/api/remote_access.swagger.dart' show Device;

class DeviceItem {
  final String? hostname;
  Uri? baseUrl;
  About? about;
  Status? status;
  Device? remoteDevice;
  String? debugHostType;
  DevicePathType? pathType;

  DeviceItem({
    this.hostname,
    this.baseUrl,
    this.about,
    this.status,
    this.remoteDevice,
    this.debugHostType,
    this.pathType,
  });

  void update({
    Uri? baseUrl,
    About? about,
    Status? status,
    String? debugHostType,
    DevicePathType? pathType,
    Device? remoteDevice,
  }) {
    if (baseUrl != null) {
      this.baseUrl = baseUrl;
    }
    if (about != null) {
      this.about = about;
    }
    if (status != null) {
      this.status = status;
    }
    if (debugHostType != null) {
      this.debugHostType = debugHostType;
    }
    if (pathType != null) {
      this.pathType = pathType;
    }
    if (remoteDevice != null) {
      this.remoteDevice = remoteDevice;
    }
  }

  String get id =>
      remoteDevice?.certificateCommonName ??
      about?.certificateCommonName ??
      'unknown_id';

  String get name =>
      hostname ?? about?.hostname ?? baseUrl?.host ?? 'Unknown Device';

  bool get isReady =>
      status == null || status!.systemState == api_enums.State.ready;
}
