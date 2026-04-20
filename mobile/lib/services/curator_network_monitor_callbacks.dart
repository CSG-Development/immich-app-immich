import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/curator_network_monitor.service.dart';
import 'package:immich_mobile/widgets/forms/login/remote_code_dialog.dart';

/// Curator UI wiring for [CuratorNetworkMonitor] (snackbars, remote OTP, API base refresh).
class CuratorAppNetworkMonitorCallbacks implements CuratorNetworkMonitorCallbacks {
  CuratorAppNetworkMonitorCallbacks(
    this._ref, {
    required Future<void> Function() retryReconnect,
  }) : _retryReconnect = retryReconnect;

  final Ref _ref;
  final Future<void> Function() _retryReconnect;

  BuildContext? get _navigatorContext =>
      _ref.read(appRouterProvider).navigatorKey.currentContext;

  @override
  void onShowReconnecting() {
    final context = _navigatorContext;
    if (context == null || !context.mounted) {
      return;
    }
    final messenger = ScaffoldMessenger.of(context);
    messenger.hideCurrentSnackBar();
    messenger.showSnackBar(
      SnackBar(
        content: Text('curator.oobe_welcome_dropdown_detecting'.tr()),
        duration: const Duration(minutes: 2),
      ),
    );
  }

  @override
  void onHideReconnecting() {
    final context = _navigatorContext;
    if (context == null || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).hideCurrentSnackBar();
  }

  @override
  Future<void> onReconnected(PingResult result) async {}

  @override
  Future<void> onNeedRemoteAccessAuth(Future<void> Function() retry) async {
    final context = _navigatorContext;
    if (context == null || !context.mounted) {
      return;
    }
    final email = _ref.read(deviceProvider).login;
    if (email.isEmpty) {
      return;
    }
    var remoteOk = false;
    await showRemoteCodeModal(
      context: context,
      initiate: _ref.read(remoteAuthProvider).initiate,
      email: email,
      onSuccess: () async {
        remoteOk = true;
      },
    );
    if (remoteOk) {
      await retry();
    }
  }

  @override
  Future<void> onReconnectionFailed() async {
    final context = _navigatorContext;
    if (context == null || !context.mounted) {
      return;
    }
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text('curator.email_unable_to_connect_description'.tr()),
        action: SnackBarAction(
          label: 'curator.button_action_retry'.tr(),
          onPressed: () => unawaited(_retryReconnect()),
        ),
      ),
    );
  }
}
