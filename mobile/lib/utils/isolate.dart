import 'dart:async';
import 'dart:ui';

import 'package:flutter/services.dart';
import 'package:hc_device/providers/hcdevice.provider.dart';
import 'package:hc_device/utils/core.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/services/log.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/providers/infrastructure/cancel.provider.dart';
import 'package:immich_mobile/providers/infrastructure/db.provider.dart';
import 'package:immich_mobile/services/api.service.dart';
import 'package:immich_mobile/utils/bootstrap.dart';
import 'package:immich_mobile/utils/secondary_runtime_api.bootstrap.dart';
import 'package:immich_mobile/infrastructure/repositories/network.repository.dart';
import 'package:immich_mobile/utils/certificates_pinning/http_cert_pinning_manager.dart';
import 'package:immich_mobile/utils/debug_print.dart';
import 'package:immich_mobile/wm_executor.dart';
import 'package:logging/logging.dart';
import 'package:worker_manager/worker_manager.dart' show Cancelable;

class InvalidIsolateUsageException implements Exception {
  const InvalidIsolateUsageException();

  @override
  String toString() => "IsolateHelper should only be used from the root isolate";
}

Cancelable<T?> runInIsolateGentle<T>({
  required Future<T> Function(ProviderContainer ref) computation,
  String? debugLabel,
}) {
  final token = RootIsolateToken.instance;
  if (token == null) {
    throw const InvalidIsolateUsageException();
  }

  return workerManagerPatch.executeGentle((onCancel) async {
    BackgroundIsolateBinaryMessenger.ensureInitialized(token);
    DartPluginRegistrant.ensureInitialized();

    NetworkRepository.enableShutdownTracking();

    final log = Logger("IsolateLogger");
    final (drift, logDb) = await Bootstrap.initDomain(shouldBufferLogs: false, listenStoreUpdates: false);

    await HttpCertPinningManager.ensureInitialized();
    await NetworkRepository.init();

    final remoteAccessDependencies = await initHCDevice(
      httpClientProvider: () => NetworkRepository.client,
      isMainRuntime: false,
    );
    final apiservice = ApiService();
    await bootstrapSecondaryRuntimeApiSession(apiservice);

    final ref = ProviderContainer(
      overrides: [
        cancellationProvider.overrideWithValue(onCancel),
        driftProvider.overrideWith(driftOverride(drift)),
        remoteAccessDependenciesProvider.overrideWithValue(remoteAccessDependencies),
        apiServiceProvider.overrideWithValue(apiservice),
      ],
    );

    try {
      return await computation(ref);
    } catch (error, stack) {
      log.severe("Error in runInIsolateGentle${debugLabel == null ? '' : ' for $debugLabel'}", error, stack);
      return null;
    } finally {
      try {
        await NetworkRepository.shutdown();
        ref.dispose();
        await Store.dispose();
        await LogService.I.dispose();
        await logDb.close();
        await drift.close();
      } catch (error, stack) {
        dPrint(() => "Error closing resources in isolate: $error, $stack");
      }
    }
  });
}
