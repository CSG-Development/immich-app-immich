import 'package:chopper/chopper.dart';
import 'package:hc_device/api/remote_access.swagger.dart'
    show Device, DevicePaths;

abstract class DeviceConnectivitySource {
  DevicePaths? getCachedDevicePaths();
  void setCachedDevicePaths(DevicePaths paths);
}

abstract class RemoteConnectivitySource {
  bool get isAuthenticated;
  Future<Response<List<Device>>> fetchDevices();
  Future<Response<DevicePaths>> fetchDevicePaths({required String deviceID});
  Future<void> logOut({bool notify});
}
