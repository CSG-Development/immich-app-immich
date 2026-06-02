
import 'package:flutter_secure_storage/flutter_secure_storage.dart'
    show FlutterSecureStorage;
import 'package:hooks_riverpod/hooks_riverpod.dart'
    show Provider, NotifierProvider;
import 'package:http/http.dart' as http;
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
  final http.Client httpClient;
  final bool isMainRuntime;

  RemoteAccessDependencies({
    required this.storageData,
    required this.secureStorage,
    required this.secureData,
    required this.httpClient,
    this.isMainRuntime = true,
  });
}

final deviceProvider = NotifierProvider<DeviceProvider, DeviceState>(
  DeviceProvider.new,
);

final remoteProvider = NotifierProvider<RemoteProvider, RemoteState>(
  RemoteProvider.new,
);
