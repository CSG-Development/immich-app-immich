import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/network.repository.dart';
import 'package:immich_mobile/providers/infrastructure/platform.provider.dart';

/// Loads pinned root CAs and configures native TLS (OkHttp, URLSession, downloader).
class HttpCertPinningManager {
  static const List<String> defaultRootCertificateAssetPaths = [
    'assets/tdci.pem',
    'assets/fake-device-noveo.cer',
  ];

  static bool _isInitialized = false;

  static Future<void> storeRootCerts(List<String> paths) async {
    final rootCertificatesPems = <String>[];
    for (final path in paths) {
      rootCertificatesPems.add(await rootBundle.loadString(path));
    }
    await Store.put(StoreKey.rootCerts, jsonEncode(rootCertificatesPems));
  }

  static Future<void> storeDefaultRootCerts() => storeRootCerts(defaultRootCertificateAssetPaths);

  static Future<List<String>> loadRootCertsBytes(List<String> paths) async {
    final certsBase64 = <String>[];
    for (final path in paths) {
      final bytes = (await rootBundle.load(path)).buffer.asUint8List();
      certsBase64.add(base64Encode(bytes));
    }
    return certsBase64;
  }

  static Future<List<String>> loadDefaultRootCertsBytes() => loadRootCertsBytes(defaultRootCertificateAssetPaths);

  /// Idempotent. Pushes roots to native pinning and initializes [NetworkRepository].
  static Future<void> ensureInitialized() async {
    if (_isInitialized) {
      return;
    }

    if (Platform.isAndroid || Platform.isIOS) {
      final encoded = await _encodedRootsForNative();
      if (encoded.isNotEmpty) {
        await networkApi.configureCertificatePinning(encoded);
      }
      await NetworkRepository.init();
    }

    _isInitialized = true;
  }

  static Future<List<String>> _encodedRootsForNative() async {
    final fromStore = _encodedRootsFromStore();
    if (fromStore.isNotEmpty) {
      return fromStore;
    }

    // Main isolate only; workers rely on [StoreKey.rootCerts] populated at startup.
    try {
      return await loadDefaultRootCertsBytes();
    } catch (_) {
      return const [];
    }
  }

  static List<String> _encodedRootsFromStore() {
    final source = Store.tryGet(StoreKey.rootCerts);
    if (source == null) {
      return const [];
    }

    final pems = (jsonDecode(source) as List).cast<String>();
    return pems.map(_pemToBase64Der).whereType<String>().toList();
  }

  static String? _pemToBase64Der(String pem) {
    final stripped = pem
        .replaceAll('-----BEGIN CERTIFICATE-----', '')
        .replaceAll('-----END CERTIFICATE-----', '')
        .replaceAll(RegExp(r'\s+'), '');
    return stripped.isEmpty ? null : stripped;
  }
}
