import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/services/endpoint_recovery.service.dart';

part 'endpoint_recovery.provider.g.dart';

@Riverpod(keepAlive: true)
EndpointRecoveryService endpointRecoveryService(Ref ref) {
  final apiService = ref.watch(apiServiceProvider);
  final service = EndpointRecoveryService(apiService, ref);
  ref.onDispose(() => service.dispose());
  return service;
}

