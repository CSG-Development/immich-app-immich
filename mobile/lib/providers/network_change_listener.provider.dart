import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/services/network_change_listener.service.dart';

final networkChangeListenerServiceProvider = Provider<NetworkChangeListenerService>((ref) {
  return NetworkChangeListenerService(ref);
});
