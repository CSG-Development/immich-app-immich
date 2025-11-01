import 'package:basic_utils/basic_utils.dart' show X509CertificateData;
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show Provider, ChangeNotifierProvider;
import 'package:homecloud_frontend/providers/device.provider.dart';
import 'package:homecloud_frontend/providers/remote.provider.dart';

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
  final X509CertificateData deviceCertificate;

  RemoteAccessDependencies({
    required this.storageData,
    required this.secureStorage,
    required this.secureData,
    required this.deviceCertificate,
  });
}

// Main DeviceProvider as ChangeNotifierProvider
final deviceProvider = ChangeNotifierProvider<DeviceProvider>((ref) {
  final deps = ref.watch(remoteAccessDependenciesProvider);
  return DeviceProvider(
    deps.storageData,
    deps.secureStorage,
    deps.secureData,
    deps.deviceCertificate,
  );
});

// Main RemoteProvider as ChangeNotifierProvider
final remoteProvider = ChangeNotifierProvider<RemoteProvider>((ref) {
  final deps = ref.watch(remoteAccessDependenciesProvider);
  return RemoteProvider(deps.storageData, deps.secureStorage, deps.secureData);
});
