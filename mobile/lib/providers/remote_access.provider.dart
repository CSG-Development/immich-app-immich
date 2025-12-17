import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:homecloud_frontend/remote_auth.provider.dart';
import 'package:immich_mobile/services/remote_access.service.dart';

/// Provider exposing [RemoteAccessService] with a shared
/// [RemoteAuthController] injected.
final remoteAccessServiceProvider = Provider<RemoteAccessService>((ref) {
  final controller = ref.read(remoteAuthProvider);
  return RemoteAccessService(controller);
});

