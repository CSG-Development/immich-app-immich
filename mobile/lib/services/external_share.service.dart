import 'dart:io';
import 'dart:ui';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/platform/share_external_api.g.dart';
import 'package:logging/logging.dart';
import 'package:share_plus/share_plus.dart';

final externalShareServiceProvider = Provider((ref) => const ExternalShareService());

class ExternalShareService {
  static final Logger _log = Logger("ExternalShareService");
  static final ShareExternalApi _api = ShareExternalApi();

  const ExternalShareService();

  Future<void> shareXFiles(List<XFile> files, {String? subject, String? text, Rect? sharePositionOrigin}) async {
    if (files.isEmpty) {
      _log.warning("Share call ignored because files list is empty");
      return;
    }

    if (Platform.isAndroid) {
      final didShareNatively = await _shareNativelyOnAndroid(files, subject: subject, text: text);
      if (didShareNatively) {
        return;
      }
    }

    await Share.shareXFiles(files, subject: subject, text: text, sharePositionOrigin: sharePositionOrigin);
  }

  Future<bool> _shareNativelyOnAndroid(List<XFile> files, {String? subject, String? text}) async {
    try {
      final didLaunch = await _api.shareFiles(
        ShareExternalRequest(paths: files.map((f) => f.path).toList(growable: false), subject: subject, text: text),
      );
      return didLaunch;
    } catch (error, stackTrace) {
      _log.warning("Native Android share failed, falling back to share_plus", error, stackTrace);
      return false;
    }
  }
}
