//   Copyright (c) 2026 Seagate Technology LLC. All rights reserved.
//
//   Complying with all applicable copyright laws is the responsibility of the user.
//   All coded instruction and program statements contained herein are, and remain,
//   copyrighted works, and are confidential proprietary information of Seagate Technology LLC or its affiliates.
//   Any use, derivation, dissemination, reproduction, or any attempt to modify, reproduce, distribute,
//   disclose copyrighted material of Seagate Technology LLC, for any reason, in any manner, medium, or form,
//   in whole or in part, if not expressly authorized, is strictly prohibited.

import 'package:flutter/material.dart' show IconData, Icons;

enum ConnectionType { local, internet }

enum NetworkMethod { ip, deviceName, direct, relay }

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

  String get defaultLabel {
    switch ((connectionType, networkMethod)) {
      case (ConnectionType.local, NetworkMethod.ip):
        return 'Local network (IP)';
      case (ConnectionType.local, NetworkMethod.deviceName):
        return 'Local network (device name)';
      case (ConnectionType.internet, NetworkMethod.direct):
        return 'Internet (direct)';
      case (ConnectionType.internet, NetworkMethod.relay):
        return 'Internet (relay)';
      default:
        return 'Connected';
    }
  }

  static ConnectionInfo? fromDebugHostType(
    String? debugHostType,
    Uri? baseUrl,
  ) {
    if (debugHostType == null || baseUrl == null) return null;

    final address =
        "${baseUrl.host}${baseUrl.hasPort ? ":${baseUrl.port}" : ""}";

    // TODO: Refactor to avoid hardcoding debugHostType values and instead use a more robust way to determine connection type and method,
    // possibly by encoding this information in the baseUrl or through additional metadata from the API.
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
