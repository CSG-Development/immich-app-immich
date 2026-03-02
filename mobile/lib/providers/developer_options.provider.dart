import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';

class DeveloperOptionsState {
  final bool devEnableSettingsOnLogin;
  final String? devStaticDeviceUrl;

  DeveloperOptionsState({required this.devEnableSettingsOnLogin, this.devStaticDeviceUrl});

  DeveloperOptionsState copyWith({bool? devEnableSettingsOnLogin, String? devStaticDeviceUrl}) {
    return DeveloperOptionsState(
      devEnableSettingsOnLogin: devEnableSettingsOnLogin ?? this.devEnableSettingsOnLogin,
      devStaticDeviceUrl: devStaticDeviceUrl ?? this.devStaticDeviceUrl,
    );
  }
}

class DeveloperOptionsStateNotifier extends StateNotifier<DeveloperOptionsState> {
  DeveloperOptionsStateNotifier()
    : super(
        DeveloperOptionsState(
          devEnableSettingsOnLogin: Store.tryGet(StoreKey.devEnableSettingsOnLogin) ?? false,
          devStaticDeviceUrl: Store.tryGet(StoreKey.devStaticDeviceUrl),
        ),
      );

  void updateDevEnableSettingsOnLogin(bool value) {
    final oldValue = state.devEnableSettingsOnLogin;
    if (oldValue != value) {
      Store.put(StoreKey.devEnableSettingsOnLogin, value);
      state = state.copyWith(devEnableSettingsOnLogin: value);
    }
  }

  void updateDevStaticDeviceUrl(String? value) {
    final oldValue = state.devStaticDeviceUrl;
    if (oldValue != value) {
      Store.put(StoreKey.devStaticDeviceUrl, value);
      state = state.copyWith(devStaticDeviceUrl: value);
    }
  }
}

final developerOptionsProvider = StateNotifierProvider<DeveloperOptionsStateNotifier, DeveloperOptionsState>(
  (ref) => DeveloperOptionsStateNotifier(),
);
