import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hc_device/api/remote_access.swagger.dart' show DevicePathType;
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/services/device_endpoint_utils.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

class LocalNetworkPreference extends HookConsumerWidget {
  const LocalNetworkPreference({super.key, required this.enabled});

  final bool enabled;

  String? _resolveLocalEndpoint(DeviceState deviceState, DeviceProvider device) {
    final allPaths = device.resolveDevicePathsForDisplay(deviceRemoteId: deviceState.seagateDeviceID);
    final localPath = allPaths
        .where((p) => p.type == DevicePathType.local)
        .map(DeviceEndpointUtils.buildDevicePathUrl)
        .cast<String?>()
        .firstWhere((url) => url != null && url.isNotEmpty, orElse: () => null);
    if (localPath != null) {
      return localPath;
    }

    final baseUrl = deviceState.baseUrl;
    if (baseUrl == null) {
      return null;
    }
    final authority = (baseUrl.hasPort && baseUrl.port > 0) ? '${baseUrl.host}:${baseUrl.port}' : baseUrl.host;
    return 'https://$authority/photos';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final deviceState = ref.watch(deviceProvider);
    final device = ref.read(deviceProvider.notifier);
    final localEndpoint = _resolveLocalEndpoint(deviceState, device) ?? '';

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
                      subtitle: localEndpoint.isEmpty
                          ? const Text("http://local-ip:2283")
                          : Text(
                              localEndpoint,
                              style: context.textTheme.labelLarge?.copyWith(
                                color: enabled ? context.primaryColor : context.colorScheme.onSurface.withAlpha(100),
                              ),
                            ),
                      trailing: const IconButton(onPressed: null, icon: Icon(Icons.edit_rounded)),
                    ),
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
