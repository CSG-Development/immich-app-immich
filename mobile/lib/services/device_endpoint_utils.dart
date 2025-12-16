import 'package:homecloud_frontend/api/remote_access.swagger.dart';

class DeviceEndpointUtils {
  const DeviceEndpointUtils._();

  static String buildDevicePathUrl(DevicePath devicePath) {
    return devicePath.port != null
        ? 'https://${devicePath.address}:${devicePath.port}/photos'
        : 'https://${devicePath.address}/photos';
  }
}
