//   Do NOT modify or remove this copyright and confidentiality notice
//
//   Copyright (c) 2025 Seagate Technology LLC or one of its affiliates.
//
//   This code is classified as SEAGATE CONFIDENTIAL
//   and may be covered under one or more Non-Disclosure Agreements.
//   Any use, modification, duplication, derivation, distribution or disclosure
//   of this code, for any reason, not expressly authorized is prohibited.
//   All other rights are expressly reserved by Seagate Technology LLC.
//

export 'package:hc_device/device_item.dart';
export 'package:hc_device/providers/device.provider.dart';
export 'package:hc_device/providers/remote.provider.dart';
export 'package:hc_device/providers/hcdevice.provider.dart';
export 'package:hc_device/utils/device_merge.dart';
export 'package:hc_device/utils/core.dart';
export 'package:hc_device/utils/mdns_platform_support.dart';
export 'package:hc_device/services/logger_service.dart';
export 'package:hc_device/services/connection_info.dart';
export 'package:hc_device/services/device_detection_service.dart'
    hide serviceTypeDiscover, timeoutLocalApiCall, timeoutRemoteApiCall;
export 'package:hc_device/services/path_probe_mode.dart';
export 'package:hc_device/services/path_resolver/hc_path_resolver.dart';
