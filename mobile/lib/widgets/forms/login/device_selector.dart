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

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:homecloud_frontend/api/api.swagger.dart';

class DeviceItem {
  final Uri? baseUrl;
  final About? about;
  final Status? status;

  DeviceItem({this.baseUrl, this.about, this.status});

  String get name => about?.hostname.isNotEmpty == true
      ? about!.hostname
      : baseUrl?.host ?? 'Unknown Device';

  bool get isReady => status == null || status!.state == StatusState.ready;

  String warnStatus(BuildContext context) {
    if (isReady) return "";
    return " (dashboard_device_card_device_status(status!.state.name))";
  }
}

class DeviceSelector extends StatefulWidget {
  final List devices;
  final dynamic selectedDevice;
  final bool isDetecting;
  final ValueChanged<dynamic> onDeviceSelected;
  final VoidCallback onRefresh;
  final FocusNode? focusNode;
  final double? maxWidth;
  final bool enabled;

  const DeviceSelector({
    super.key,
    required this.devices,
    required this.selectedDevice,
    this.isDetecting = false,
    required this.onDeviceSelected,
    required this.onRefresh,
    this.focusNode,
    this.maxWidth,
    this.enabled = true,
  });

  @override
  State<DeviceSelector> createState() => _DeviceSelectorState();
}

class _DeviceSelectorState extends State<DeviceSelector> {
  Widget _buildIconDevice(DeviceItem? device) {
    late Widget icon;
    if (device == null) {
      if (widget.isDetecting) {
        icon = const Icon(Icons.search, size: 32);
      } else {
        icon = const Icon(Icons.cloud_off, size: 32, color: Colors.red);
      }
    } else {
      icon = Image.asset("assets/device.webp", width: 50, height: 40);
    }
    return SizedBox(height: 40.0, width: 50.0, child: icon);
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Expanded(
          child: DropdownMenu<DeviceItem>(
            label: Text(
              widget.isDetecting
                  ? 'curator.oobe_welcome_dropdown_detecting'.tr()
                  : 'curator.sign_in_screen_dropdown_device_label'.tr(),
            ),
            width: widget.maxWidth != null ? widget.maxWidth! - 12 - 24 : null,
            initialSelection: widget.selectedDevice,
            requestFocusOnTap: false,
            focusNode: widget.focusNode,
            enabled: widget.enabled,
            onSelected: widget.onDeviceSelected,
            errorText: widget.devices.isEmpty && !widget.isDetecting
                ? 'curator.sign_in_screen_dropdown_device_error_no_device'.tr()
                : null,
            leadingIcon: Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: _buildIconDevice(widget.selectedDevice),
            ),
            dropdownMenuEntries: widget.devices.map((device) {
              return DropdownMenuEntry<DeviceItem>(
                value: device,
                label: device.name + device.warnStatus(context),
                leadingIcon: _buildIconDevice(device),
                enabled: device.isReady,
              );
            }).toList(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: SizedBox(
            height: 24.0,
            width: 24.0,
            child: widget.isDetecting
                ? const CircularProgressIndicator.adaptive()
                : IconButton(
                    icon: const Icon(Icons.refresh),
                    padding: EdgeInsets.zero,
                    onPressed: widget.onRefresh,
                  ),
          ),
        ),
      ],
    );
  }
}
