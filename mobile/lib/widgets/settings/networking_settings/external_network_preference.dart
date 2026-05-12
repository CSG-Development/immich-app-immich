import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hc_device/api/remote_access.swagger.dart' show DevicePath, DevicePathType;
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/services/device_endpoint_utils.dart';
import 'package:hc_device/hc_device.dart';

class ExternalNetworkPreference extends HookConsumerWidget {
  const ExternalNetworkPreference({super.key, required this.enabled});

  final bool enabled;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(deviceProvider);
    final device = ref.read(deviceProvider.notifier);
    final activePaths = device.getActiveDevicePaths(deviceRemoteId: deviceState.seagateDeviceID);
    final cachedPaths = deviceState.seagateDeviceID == null
        ? null
        : device.getCachedDevicePathsForDevice(deviceState.seagateDeviceID!);
    final allPaths = (activePaths ?? cachedPaths?.paths ?? const <DevicePath>[])
        .whereType<DevicePath>()
        .toList();
    final externalPaths = allPaths
        .where((path) => path.type != DevicePathType.local)
        .where((path) => path.type != DevicePathType.swaggerGeneratedUnknown)
        .map(DeviceEndpointUtils.buildDevicePathUrl)
        .toSet()
        .toList();

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0),
      child: Container(
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
              child: Icon(Icons.dns_rounded, size: 120, color: context.primaryColor.withValues(alpha: 0.05)),
            ),
            ListView(
              padding: const EdgeInsets.symmetric(vertical: 16.0),
              physics: const ClampingScrollPhysics(),
              shrinkWrap: true,
              children: [
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 4.0, horizontal: 24),
                  child: Text("external_network_sheet_info".tr(), style: context.textTheme.bodyMedium),
                ),
                const SizedBox(height: 4),
                Divider(color: context.colorScheme.surfaceContainerHighest),
                if (externalPaths.isEmpty)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(24, 12, 24, 16),
                    child: Text(
                      'No external paths available from hc_device',
                      style: context.textTheme.bodyMedium?.copyWith(
                        color: context.colorScheme.onSurface.withValues(alpha: 0.7),
                      ),
                    ),
                  )
                else
                  ...externalPaths.map(
                    (endpoint) => ListTile(
                      enabled: enabled,
                      contentPadding: const EdgeInsets.symmetric(horizontal: 24),
                      leading: const Icon(Icons.check_circle_rounded, color: Colors.green),
                      title: Text(
                        endpoint,
                        style: context.textTheme.bodyMedium?.copyWith(
                          fontWeight: FontWeight.w600,
                          color: enabled
                              ? context.primaryColor
                              : context.colorScheme.onSurface.withValues(alpha: 0.6),
                        ),
                      ),
                      subtitle: Text(
                        'From hc_device discovered paths',
                        style: context.textTheme.bodySmall,
                      ),
                    ),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
