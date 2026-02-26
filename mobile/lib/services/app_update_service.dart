import 'dart:async';

import 'package:flutter/material.dart';
import 'package:immich_mobile/platform/update_api.g.dart';
import 'package:immich_mobile/utils/env_config.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:immich_mobile/widgets/update/update_dialog.dart';
import 'package:flutter/foundation.dart' show defaultTargetPlatform, TargetPlatform;
import 'dart:io' show Platform;

class _UpdateCallbacksImpl extends UpdateCallbacks {
  _UpdateCallbacksImpl(this.onProgress, this.onError, this.onCompleted);
  final void Function(DownloadProgress) onProgress;
  final void Function(String) onError;
  final VoidCallback onCompleted;

  @override
  void onDownloadCompleted() => onCompleted();

  @override
  void onDownloadError(String message) => onError(message);

  @override
  void onDownloadProgress(DownloadProgress progress) => onProgress(progress);
}

class AppUpdateService {
  final _log = Logger('AppUpdateService');
  final UpdateApi _updateApi = UpdateApi();

  Future<void> checkOnStart({required BuildContext context}) async {
    final bool isAndroid = defaultTargetPlatform == TargetPlatform.android && Platform.isAndroid;
    if (!isAndroid) {
      _log.info("checkOnStart skipped: non-Android");
      return;
    }

    UpdateCallbacks.setUp(_UpdateCallbacksImpl((_) {}, (_) {}, () {}));
    _log.info("checkOnStart invoked");

    try {
      final updateUrl = await EnvConfig.get(EnvKey.updateUrl);
      if (updateUrl == null || updateUrl.isEmpty) {
        _log.info("checkOnStart skipped: UPDATE_URL not configured");
        return;
      }

      final info = await _updateApi.fetchLatestUpdate(updateUrl);
      _log.info("checkOnStart info: ${info?.version ?? 'null'}");
      if (info == null) return;

      final pkg = await PackageInfo.fromPlatform();

      final localVersionString = _extractVersion(pkg.version);
      final remoteVersionString = _extractVersion(info.version);

      Version local;
      Version remote;
      try {
        local = Version.parse(localVersionString);
        remote = Version.parse(remoteVersionString);
      } catch (e, stack) {
        _log.warning(
          "checkOnStart failed to parse versions local='$localVersionString' remote='$remoteVersionString'",
          e,
          stack,
        );
        return;
      }

      _log.info("local=$local remote=$remote");
      if (remote <= local) {
        _log.info("No update needed");
        return;
      }

      _log.info("show_update_dialog version=${info.version}");
      await showUpdateAvailableDialog(
        context: context,
        version: info.version,
        changelog: info.changelog,
        forced: false,
        downloadUrl: info.url,
        sha256: info.sha256,
      );
    } catch (e, stack) {
      _log.severe("checkOnStart failed", e, stack);
    }
  }

  String _extractVersion(String version) {
    final match = RegExp(r'^(\d+\.\d+\.\d+)').firstMatch(version);
    return match?.group(1) ?? version;
  }
}
