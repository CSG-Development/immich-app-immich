import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/services/app_update_service.dart';

final appUpdateServiceProvider = Provider<AppUpdateService>((ref) {
  return AppUpdateService();
});


