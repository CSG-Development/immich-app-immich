import 'package:hooks_riverpod/hooks_riverpod.dart';

class RecoveryStatus {
  final bool isRecovering;
  final String? currentEndpoint;
  final DateTime? recoveryStartTime;

  const RecoveryStatus({
    this.isRecovering = false,
    this.currentEndpoint,
    this.recoveryStartTime,
  });

  RecoveryStatus copyWith({
    bool? isRecovering,
    String? currentEndpoint,
    DateTime? recoveryStartTime,
  }) {
    return RecoveryStatus(
      isRecovering: isRecovering ?? this.isRecovering,
      currentEndpoint: currentEndpoint ?? this.currentEndpoint,
      recoveryStartTime: recoveryStartTime ?? this.recoveryStartTime,
    );
  }

  @override
  bool operator ==(Object other) {
    if (identical(this, other)) return true;
    return other is RecoveryStatus &&
        other.isRecovering == isRecovering &&
        other.currentEndpoint == currentEndpoint &&
        other.recoveryStartTime == recoveryStartTime;
  }

  @override
  int get hashCode => Object.hash(isRecovering, currentEndpoint, recoveryStartTime);
}

class RecoveryStatusNotifier extends StateNotifier<RecoveryStatus> {
  RecoveryStatusNotifier() : super(const RecoveryStatus());

  void startRecovery(String? endpoint) {
    state = RecoveryStatus(
      isRecovering: true,
      currentEndpoint: endpoint,
      recoveryStartTime: DateTime.now(),
    );
  }

  void stopRecovery() {
    state = const RecoveryStatus(isRecovering: false);
  }

  void updateEndpoint(String? endpoint) {
    if (state.isRecovering) {
      state = state.copyWith(currentEndpoint: endpoint);
    }
  }
}

final recoveryStatusProvider = StateNotifierProvider<RecoveryStatusNotifier, RecoveryStatus>((ref) {
  return RecoveryStatusNotifier();
});
