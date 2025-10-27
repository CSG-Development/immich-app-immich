import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:logging/logging.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pub_semver/pub_semver.dart';
import 'package:immich_mobile/platform/update_api.g.dart';
import 'package:immich_mobile/widgets/dialogs/update_dialog.dart';
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
  final UpdateApi _api = UpdateApi();

  Future<void> checkOnStart({required BuildContext context}) async {
    // Guard by platform/flavor: Android sideload only
    final bool isAndroid = defaultTargetPlatform == TargetPlatform.android && Platform.isAndroid;
    if (!isAndroid) {
      _log.info("checkOnStart skipped: non-Android");
      return;
    }
    // Register callbacks (no-op; dialog will override as needed)
    UpdateCallbacks.setUp(_UpdateCallbacksImpl((_) {}, (_) {}, () {}));
    _log.info("checkOnStart invoked");

    const env = String.fromEnvironment('ENVIRONMENT', defaultValue: 'prod');
    await dotenv.load(fileName: '.env.$env');
    final updateUrl = dotenv.env['UPDATE_URL'];
    if (updateUrl == null) return;

    final info = await _api.fetchLatestUpdate(updateUrl);
    _log.info("checkOnStart info: ${info?.version ?? 'null'}");
    if (info == null) return;
    final pkg = await PackageInfo.fromPlatform();

    final localVersionString = _extractVersion(pkg.version);
    final remoteVersionString = _extractVersion(info.version);

    final local = Version.parse(localVersionString);
    final remote = Version.parse(remoteVersionString);
    _log.info("local=${local.toString()} remote=${remote.toString()}");
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
  }

  String _extractVersion(String version) {
    final match = RegExp(r'^(\d+\.\d+\.\d+)').firstMatch(version);
    return match?.group(1) ?? version;
  }
}
