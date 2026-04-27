//   Do NOT modify or remove this copyright and confidentiality notice
//
//   Copyright (c) 2026 Seagate Technology LLC or one of its affiliates.
//
//   This code is classified as SEAGATE CONFIDENTIAL
//   and may not be used, modified, duplicated, derived, distributed, or disclosed
//   except as expressly authorized.

import 'package:flutter/material.dart';

/// High-level connection category.
enum ConnectionType { local, internet }

enum NetworkMethod { ip, deviceName, direct, relay }

/// Stable key for host-app localization.
enum ConnectionLabelKind {
  localIp,
  localDeviceName,
  internetDirect,
  internetRelay,
  unknown,
}

/// UI metadata for the active Curator connection path.
class ConnectionInfo {
  final IconData icon;
  final ConnectionType connectionType;
  final NetworkMethod networkMethod;
  final String address;

  const ConnectionInfo({
    required this.icon,
    required this.connectionType,
    required this.networkMethod,
    required this.address,
  });

  ConnectionLabelKind get labelKind => switch ((connectionType, networkMethod)) {
        (ConnectionType.local, NetworkMethod.ip) => ConnectionLabelKind.localIp,
        (ConnectionType.local, NetworkMethod.deviceName) => ConnectionLabelKind.localDeviceName,
        (ConnectionType.internet, NetworkMethod.direct) => ConnectionLabelKind.internetDirect,
        (ConnectionType.internet, NetworkMethod.relay) => ConnectionLabelKind.internetRelay,
        _ => ConnectionLabelKind.unknown,
      };

  /// English fallback when the host has no i18n mapping for [labelKind].
  String get defaultLabel => switch (labelKind) {
        ConnectionLabelKind.localIp => 'Local network (IP)',
        ConnectionLabelKind.localDeviceName => 'Local network (device name)',
        ConnectionLabelKind.internetDirect => 'Internet (direct)',
        ConnectionLabelKind.internetRelay => 'Internet (relay)',
        ConnectionLabelKind.unknown => 'Connected',
      };

  static ConnectionInfo? fromDebugHostType(
    String? debugHostType,
    Uri? baseUrl,
  ) {
    if (debugHostType == null || baseUrl == null) return null;

    final address =
        '${baseUrl.host}${baseUrl.hasPort ? ':${baseUrl.port}' : ''}';

    switch (debugHostType) {
      case 'Remote Access > local':
      case 'Development':
      case 'Web App':
      case 'Bluetooth OOBE':
        return ConnectionInfo(
          icon: Icons.lan,
          connectionType: ConnectionType.local,
          networkMethod: NetworkMethod.ip,
          address: address,
        );
      case 'mDNS':
        return ConnectionInfo(
          icon: Icons.lan,
          connectionType: ConnectionType.local,
          networkMethod: NetworkMethod.deviceName,
          address: address,
        );
      case 'Remote Access > public':
        return ConnectionInfo(
          icon: Icons.public,
          connectionType: ConnectionType.internet,
          networkMethod: NetworkMethod.direct,
          address: address,
        );
      case 'Remote Access > remote':
        return ConnectionInfo(
          icon: Icons.cloud,
          connectionType: ConnectionType.internet,
          networkMethod: NetworkMethod.relay,
          address: address,
        );
      default:
        if (debugHostType.startsWith('Remote Access')) {
          return ConnectionInfo(
            icon: Icons.question_mark,
            connectionType: ConnectionType.internet,
            networkMethod: NetworkMethod.direct,
            address: address,
          );
        }
        return null;
    }
  }
}
