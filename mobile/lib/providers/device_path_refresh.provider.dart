import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/services/device_path_refresh.service.dart';

/// Provider for DevicePathRefreshService
final devicePathRefreshServiceProvider = Provider<DevicePathRefreshService>((ref) {
  return DevicePathRefreshService(ref);
});
