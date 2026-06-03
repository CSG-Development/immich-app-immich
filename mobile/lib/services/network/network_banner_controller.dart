import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/widgets/common/network_status_snackbar.widget.dart';

enum NetworkBannerKind { hidden, finding, noInternet, unable }

class NetworkBannerController {
  NetworkBannerController({
    required BuildContext? Function() contextGetter,
    required VoidCallback onFindingDismissed,
    required VoidCallback onRetry,
    Duration findingDelay = const Duration(milliseconds: 200),
  }) : _contextGetter = contextGetter,
       _onFindingDismissed = onFindingDismissed,
       _onRetry = onRetry,
       _findingDelay = findingDelay;

  final BuildContext? Function() _contextGetter;
  final VoidCallback _onFindingDismissed;
  final VoidCallback _onRetry;
  final Duration _findingDelay;

  final ValueNotifier<NetworkBannerKind> _kind = ValueNotifier(NetworkBannerKind.hidden);
  Timer? _findingTimer;
  ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? _bannerController;
  bool _isBannerClosing = false;

  NetworkBannerKind get activeKind => _kind.value;

  void transitionTo(NetworkBannerKind desired) {
    if (desired == activeKind) {
      return;
    }

    if (desired == NetworkBannerKind.hidden) {
      _findingTimer?.cancel();
      _findingTimer = null;
      _hideBanner();
      return;
    }

    if (desired == NetworkBannerKind.unable || desired == NetworkBannerKind.noInternet) {
      _findingTimer?.cancel();
      _findingTimer = null;
      _showNow(desired);
      return;
    }

    _findingTimer?.cancel();
    _findingTimer = Timer(_findingDelay, () {
      _findingTimer = null;
      if (activeKind == NetworkBannerKind.hidden || activeKind == NetworkBannerKind.unable || activeKind == NetworkBannerKind.noInternet) {
        _showNow(NetworkBannerKind.finding);
      }
    });
  }

  void dispose() {
    _findingTimer?.cancel();
    _findingTimer = null;
    _hideBanner();
    _kind.dispose();
  }

  void _showNow(NetworkBannerKind kind) {
    if (_isBannerClosing || kind == NetworkBannerKind.hidden) {
      return;
    }
    _ensureBannerVisible();
    _kind.value = kind;
  }

  void _ensureBannerVisible() {
    if (_bannerController != null) {
      return;
    }
    final context = _contextGetter();
    if (context == null || !context.mounted) {
      return;
    }

    _isBannerClosing = false;
    final controller = ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        dismissDirection: DismissDirection.none,
        duration: const Duration(days: 30),
        backgroundColor: Colors.transparent,
        elevation: 0,
        margin: const EdgeInsets.fromLTRB(8, 0, 8, 8),
        padding: EdgeInsets.zero,
        content: _ReactiveNetworkStatusSnackBar(
          kindListenable: _kind,
          onClose: _onBannerClose,
          onRetry: _onRetry,
        ),
      ),
    );
    _bannerController = controller;
    unawaited(
      controller.closed.whenComplete(() {
        _isBannerClosing = false;
        if (identical(_bannerController, controller)) {
          _bannerController = null;
        }
      }),
    );
  }

  void _hideBanner() {
    _kind.value = NetworkBannerKind.hidden;
    final controller = _bannerController;
    if (controller != null) {
      _isBannerClosing = true;
      controller.close();
    } else {
      _isBannerClosing = false;
    }
  }

  void _onBannerClose() {
    if (_kind.value == NetworkBannerKind.finding) {
      _onFindingDismissed();
    }
    _hideBanner();
  }
}

class _ReactiveNetworkStatusSnackBar extends StatelessWidget {
  const _ReactiveNetworkStatusSnackBar({
    required this.kindListenable,
    required this.onClose,
    required this.onRetry,
  });

  final ValueListenable<NetworkBannerKind> kindListenable;
  final VoidCallback onClose;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<NetworkBannerKind>(
      valueListenable: kindListenable,
      builder: (_, kind, __) {
        final isError = kind == NetworkBannerKind.unable || kind == NetworkBannerKind.noInternet;
        final message = switch (kind) {
          NetworkBannerKind.noInternet => 'curator.network.no_internet'.tr(),
          NetworkBannerKind.unable => 'errors.unable_to_connect'.tr(),
          _ => 'curator.network.finding'.tr(),
        };
        return NetworkStatusSnackBar(
          message: message,
          onClose: onClose,
          onRetry: isError ? onRetry : null,
          retryLabel: isError ? 'retry'.tr() : null,
        );
      },
    );
  }
}
