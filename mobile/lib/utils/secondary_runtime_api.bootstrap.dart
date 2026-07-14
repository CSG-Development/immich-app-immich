import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/providers/network/network_monitor.provider.dart';
import 'package:immich_mobile/services/api.service.dart';

/// Prepares API auth headers for secondary runtimes (background worker, worker isolates).
Future<void> bootstrapSecondaryRuntimeApiSession(ApiService apiService) async {
  final accessToken = Store.tryGet(StoreKey.accessToken);
  if (accessToken != null && accessToken.isNotEmpty) {
    await apiService.setAccessToken(accessToken);
    return;
  }

  await apiService.updateHeaders();
}

/// Resolves and activates the best endpoint for a secondary runtime.
Future<String?> bootstrapSecondaryRuntimeEndpoint(
  ProviderContainer ref, {
  required String trigger,
  ResolveMode mode = ResolveMode.foreground,
  String? runId,
}) {
  return ref
      .read(hcDeviceEndpointResolverProvider)
      .resolveAndActivateWinner(runId: runId, trigger: trigger, mode: mode);
}
