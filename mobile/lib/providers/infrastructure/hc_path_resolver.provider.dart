import 'dart:async';

import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

final hcPathResolverProvider = Provider<HcPathResolver>((ref) {
  final resolver = HcPathResolver(
    deviceProvider: ref.read(deviceProvider.notifier),
    remoteProvider: ref.read(remoteProvider.notifier),
  );
  ref.onDispose(() {
    unawaited(resolver.dispose());
  });
  return resolver;
});

final hcPathResolverBootstrapProvider = FutureProvider<void>((ref) async {
  await ref.read(hcPathResolverProvider).init();
});
