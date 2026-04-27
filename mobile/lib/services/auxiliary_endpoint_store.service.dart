import 'dart:convert';

import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/models/auth/auxilary_endpoint.model.dart';
import 'package:logging/logging.dart';

/// Persistence helper for external auxiliary endpoints stored in [StoreKey.externalEndpointList].
class AuxiliaryEndpointStoreService {
  AuxiliaryEndpointStoreService._();

  static final Logger _log = Logger('AuxiliaryEndpointStoreService');

  static List<AuxilaryEndpoint> loadAll() {
    final jsonString = Store.tryGet(StoreKey.externalEndpointList);
    if (jsonString == null) {
      return [];
    }

    try {
      final List<dynamic> jsonList = jsonDecode(jsonString);
      return jsonList.map((e) => AuxilaryEndpoint.fromJson(e)).toList();
    } catch (error, stackTrace) {
      _log.warning('Failed to parse external endpoint list, returning empty list', error, stackTrace);
      return [];
    }
  }

  static List<AuxilaryEndpoint> loadValid() =>
      loadAll().where((e) => e.status == AuxCheckStatus.valid).toList(growable: false);

  static Future<void> saveValid(List<AuxilaryEndpoint> endpoints) async {
    final validEndpoints = endpoints.where((e) => e.status == AuxCheckStatus.valid).toList(growable: false);
    await Store.put(StoreKey.externalEndpointList, jsonEncode(validEndpoints));
  }

  static Future<bool> addValidIfMissing(String url) async {
    final endpoints = loadAll();
    final exists = endpoints.any((e) => e.url == url);
    if (exists) {
      return false;
    }

    endpoints.add(AuxilaryEndpoint(url: url, status: AuxCheckStatus.valid));
    await saveValid(endpoints);
    return true;
  }
}
