import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/services/local_auth.service.dart';

final localAuthServiceProvider = Provider<LocalAuthService>((ref) {
  return LocalAuthService();
}); 