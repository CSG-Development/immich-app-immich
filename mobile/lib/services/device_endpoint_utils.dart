import 'package:hc_device/api/remote_access.swagger.dart';

class DeviceEndpointUtils {
  const DeviceEndpointUtils._();

  static String buildDevicePathUrl(DevicePath devicePath) {
    return devicePath.port != null
        ? 'https://${devicePath.address}:${devicePath.port}/photos'
        : 'https://${devicePath.address}/photos';
  }

  static List<DevicePath> sortPathsForConnectionProbe(List<DevicePath> paths) {
    final locals = <DevicePath>[];
    final publics = <DevicePath>[];
    final remotes = <DevicePath>[];
    final unknown = <DevicePath>[];
    for (final p in paths) {
      switch (p.type) {
        case DevicePathType.local:
          locals.add(p);
        case DevicePathType.public:
          publics.add(p);
        case DevicePathType.remote:
          remotes.add(p);
        case DevicePathType.swaggerGeneratedUnknown:
          unknown.add(p);
      }
    }
    return <DevicePath>[
      ...locals,
      ...publics,
      ...remotes,
      ...unknown,
    ];
  }

  static List<String> buildSortedAuxiliaryEndpoints(List<DevicePath> paths) =>
      sortPathsForConnectionProbe(paths).map(buildDevicePathUrl).toList(growable: false);
}
