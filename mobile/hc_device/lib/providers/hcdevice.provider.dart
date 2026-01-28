
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show Provider, ChangeNotifierProvider;
import 'package:hc_device/providers/device.provider.dart';
import 'package:hc_device/providers/remote.provider.dart';

// Provider for DeviceProvider dependencies
final remoteAccessDependenciesProvider = Provider<RemoteAccessDependencies>((
  ref,
) {
  throw UnimplementedError('DeviceDependencies must be provided via override');
});

class RemoteAccessDependencies {
  final Map<String, dynamic> storageData;
  final FlutterSecureStorage secureStorage;
  final Map<String, String> secureData;
  final Future<void> Function({required String host, int? port}) registerHostTrustedChain;

  RemoteAccessDependencies({
    required this.storageData,
    required this.secureStorage,
    required this.secureData,
    required this.registerHostTrustedChain
  });
}

// Main DeviceProvider as ChangeNotifierProvider
final deviceProvider = ChangeNotifierProvider<DeviceProvider>((ref) {
  final deps = ref.watch(remoteAccessDependenciesProvider);
  return DeviceProvider(
    deps.storageData,
    deps.secureStorage,
    deps.secureData,
    deps.registerHostTrustedChain
  );
});

// Main RemoteProvider as ChangeNotifierProvider
final remoteProvider = ChangeNotifierProvider<RemoteProvider>((ref) {
  final deps = ref.watch(remoteAccessDependenciesProvider);
  return RemoteProvider(deps.storageData, deps.secureStorage, deps.secureData);
});
