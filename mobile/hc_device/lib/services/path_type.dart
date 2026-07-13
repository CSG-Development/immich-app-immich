import 'package:hc_device/api/remote_access.enums.swagger.dart' show DevicePathType;

/// The three path types from the Home Cloud backend ([DevicePathType]).
class HcPathType {
  HcPathType._();

  static const local = 'local';
  static const public = 'public';
  static const remote = 'remote';

  static const values = [local, public, remote];

  static bool isKnown(String? value) => value != null && values.contains(value);

  static String? fromDevicePathType(DevicePathType? type) {
    return switch (type) {
      DevicePathType.local => local,
      DevicePathType.public => public,
      DevicePathType.remote => remote,
      DevicePathType.swaggerGeneratedUnknown || null => null,
    };
  }

  static DevicePathType? toDevicePathType(String? value) {
    return switch (value) {
      local => DevicePathType.local,
      public => DevicePathType.public,
      remote => DevicePathType.remote,
      _ => null,
    };
  }
}
