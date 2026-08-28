import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';

enum AppSettingsEnum<T> {
  advancedTroubleshooting<bool>(StoreKey.advancedTroubleshooting, null, false),
  manageLocalMediaAndroid<bool>(StoreKey.manageLocalMediaAndroid, null, false),
  allowSelfSignedSSLCert<bool>(StoreKey.selfSignedCert, null, false),
  enableHapticFeedback<bool>(StoreKey.enableHapticFeedback, null, true),
  readonlyModeEnabled<bool>(StoreKey.readonlyModeEnabled, "readonlyModeEnabled", false),
  backupUploadTelemetry<bool>(StoreKey.backupUploadTelemetry, null, true),
  enableBiometric<bool>(StoreKey.enableBiometric, null, false),
  appLockTimeoutIndex<int>(StoreKey.appLockTimeoutIndex, null, 0);

  const AppSettingsEnum(this.storeKey, this.hiveKey, this.defaultValue);

  final StoreKey<T> storeKey;
  final String? hiveKey;
  final T defaultValue;
}

class AppSettingsService {
  const AppSettingsService();
  T getSetting<T>(AppSettingsEnum<T> setting) {
    return Store.get(setting.storeKey, setting.defaultValue);
  }

  Future<void> setSetting<T>(AppSettingsEnum<T> setting, T value) {
    return Store.put(setting.storeKey, value);
  }
}
