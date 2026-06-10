import 'dart:async';

import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hc_device/api/remote_access.swagger.dart' show DevicePath, DevicePathType;
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/services/device_endpoint_utils.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/network.provider.dart';

class LocalNetworkPreference extends HookConsumerWidget {
  const LocalNetworkPreference({super.key, required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localEndpointText = useState('');

    useEffect(() {
      final deviceState = ref.read(deviceProvider);
      final device = ref.read(deviceProvider.notifier);
      final activePaths = device.getActiveDevicePaths(deviceRemoteId: deviceState.seagateDeviceID);
      final cachedPaths = deviceState.seagateDeviceID == null
          ? null
          : device.getCachedDevicePathsForDevice(deviceState.seagateDeviceID!);
      final allPaths = activePaths ?? cachedPaths?.paths ?? const [];
      final localPath = allPaths
          .where((p) => p.type == DevicePathType.local)
          .cast<DevicePath>()
          .map(DeviceEndpointUtils.buildDevicePathUrl)
          .cast<String?>()
          .firstWhere((url) => url != null && url.isNotEmpty, orElse: () => null);
      if (localPath != null) {
        localEndpointText.value = localPath;
      }
      return null;
    }, [ref.watch(deviceProvider)]);

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Stack(
        children: [
          Container(
            clipBehavior: Clip.antiAlias,
            decoration: BoxDecoration(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              color: context.colorScheme.surfaceContainerLow,
              border: Border.all(color: context.colorScheme.surfaceContainerHighest, width: 1),
            ),
            child: Stack(
              children: [
                Positioned(
                  bottom: -36,
                  right: -36,
                  child: Icon(Icons.home_outlined, size: 120, color: context.primaryColor.withValues(alpha: 0.05)),
                ),
                ListView(
                  padding: const EdgeInsets.symmetric(vertical: 16.0),
                  physics: const ClampingScrollPhysics(),
                  shrinkWrap: true,
                  children: [
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 24),
                      child: Text("local_network_sheet_info".t(context: context), style: context.textTheme.bodyMedium),
                    ),
                    const SizedBox(height: 4),
                    Divider(color: context.colorScheme.surfaceContainerHighest),
                    ListTile(
                      enabled: enabled,
                      contentPadding: const EdgeInsets.only(left: 24, right: 8),
                      leading: const Icon(Icons.lan_rounded),
                      title: Text("server_endpoint".t(context: context)),
                      subtitle: localEndpointText.value.isEmpty
                          ? const Text("http://local-ip:2283")
                          : Text(
                              localEndpointText.value,
                              style: context.textTheme.labelLarge?.copyWith(
                                color: enabled ? context.primaryColor : context.colorScheme.onSurface.withAlpha(100),
                              ),
                            ),
                      trailing: const IconButton(onPressed: null, icon: Icon(Icons.edit_rounded)),
                    ),
                    // const SizedBox(height: 16),
                    // Padding(
                    //   padding: const EdgeInsets.symmetric(horizontal: 24.0),
                    //   child: SizedBox(
                    //     height: 48,
                    //     child: OutlinedButton.icon(
                    //       icon: const Icon(Icons.wifi_find_rounded),
                    //       label: Text('use_current_connection'.tr().toUpperCase()),
                    //       onPressed: enabled ? autofillCurrentNetwork : null,
                    //     ),
                    //   ),
                    // ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
