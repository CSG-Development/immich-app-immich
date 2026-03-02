import 'dart:async';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/auth/auth_state.model.dart';
import 'package:immich_mobile/providers/auth.provider.dart';

class ProtectedFeatureVisibilityState {
  final bool isVisible;

  const ProtectedFeatureVisibilityState({this.isVisible = false});

  ProtectedFeatureVisibilityState copyWith({bool? isVisible}) =>
      ProtectedFeatureVisibilityState(isVisible: isVisible ?? this.isVisible);
}

/// StateNotifier that exposes per-session visibility for protected features.
///
/// - If authenticated: feature is visible by default.
/// - If unauthenticated: requires 5 taps within 2 seconds to reveal.
class ProtectedFeatureVisibilityNotifier extends StateNotifier<ProtectedFeatureVisibilityState> {
  final Ref _ref;

  Timer? _resetTimer;
  int _tapCount = 0;

  ProtectedFeatureVisibilityNotifier(
    this._ref, {
    required bool isAuthenticated,
  }) : super(ProtectedFeatureVisibilityState(isVisible: isAuthenticated)) {
    _ref.listen<AuthState>(authProvider, (previous, next) {
      if (next.isAuthenticated && !state.isVisible) {
        state = state.copyWith(isVisible: true);
      }
      // Do not reset on unauthenticated – keep visibility for the session once unlocked.
    });
  }

  /// Call on the relevant UI element tap to progress the unlock sequence.
  void handleTap() {
    final isAuthenticated = _ref.read(authProvider).isAuthenticated;

    // Already visible or authenticated -> nothing to do.
    if (state.isVisible || isAuthenticated) {
      if (!state.isVisible && isAuthenticated) {
        state = state.copyWith(isVisible: true);
      }
      return;
    }

    _tapCount++;
    _resetTimer?.cancel();

    if (_tapCount >= 5) {
      state = state.copyWith(isVisible: true);
      _tapCount = 0;
      return;
    }

    _resetTimer = Timer(const Duration(seconds: 2), () {
      _tapCount = 0;
    });
  }

  @override
  void dispose() {
    _resetTimer?.cancel();
    super.dispose();
  }
}

final protectedFeatureVisibilityProvider =
    StateNotifierProvider<ProtectedFeatureVisibilityNotifier, ProtectedFeatureVisibilityState>((ref) {
  final isAuthenticated = ref.watch(authProvider).isAuthenticated;
  return ProtectedFeatureVisibilityNotifier(ref, isAuthenticated: isAuthenticated);
});
