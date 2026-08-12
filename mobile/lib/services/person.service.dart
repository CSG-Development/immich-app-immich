import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/person.model.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:immich_mobile/repositories/asset.repository.dart';
import 'package:immich_mobile/repositories/asset_api.repository.dart';
import 'package:immich_mobile/repositories/person_api.repository.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';
import 'package:riverpod_annotation/riverpod_annotation.dart';

part 'person.service.g.dart';

@riverpod
PersonService personService(Ref ref) => PersonService(
  ref.watch(personApiRepositoryProvider),
  ref.watch(assetApiRepositoryProvider),
  ref.read(assetRepositoryProvider),
);

class PersonService {
  final Logger _log = Logger("PersonService");
  final PersonApiRepository _personApiRepository;
  final AssetApiRepository _assetApiRepository;
  final AssetRepository _assetRepository;

  PersonService(this._personApiRepository, this._assetApiRepository, this._assetRepository);

  Future<List<PersonDto>> getAllPeople({String? closestPersonId}) async {
    try {
      return await _personApiRepository.getAll(closestPersonId: closestPersonId);
    } catch (error, stack) {
      _log.severe("Error while fetching curated people", error, stack);
      rethrow;
    }
  }

  Future<List<Asset>> getPersonAssets(String id) async {
    try {
      final assets = await _assetApiRepository.search(personIds: [id]);
      final localAssets = await _assetRepository.getAllByRemoteId(assets.map((a) => a.remoteId!));
      final localIds = localAssets.map((a) => a.remoteId).whereType<String>().toSet();
      final missingAssets = assets.where((asset) => !localIds.contains(asset.remoteId)).toList();

      final assetsByRemoteId = <String, Asset>{
        for (final asset in localAssets)
          if (asset.remoteId != null) asset.remoteId!: asset,
        for (final asset in missingAssets)
          if (asset.remoteId != null) asset.remoteId!: asset,
      };

      return assets.map((asset) => assetsByRemoteId[asset.remoteId!]).whereType<Asset>().toList();
    } catch (error, stack) {
      _log.severe("Error while fetching person assets", error, stack);
    }
    return [];
  }

  Future<PersonDto?> get(String id) async {
    try {
      return await _personApiRepository.get(id);
    } catch (error, stack) {
      _log.severe("Error while fetching person", error, stack);
    }
    return null;
  }

  Future<PersonDto?> updateName(String id, String name) async {
    try {
      return await _personApiRepository.update(id, name: name);
    } catch (error, stack) {
      _log.severe("Error while updating person name", error, stack);
    }
    return null;
  }

  Future<PersonDto?> updateFavorite(String id, bool isFavorite) async {
    try {
      return await _personApiRepository.update(id, isFavorite: isFavorite);
    } catch (error, stack) {
      _log.severe("Error while updating person favorite state", error, stack);
    }
    return null;
  }

  Future<List<BulkIdResponseDto>?> mergePerson(String id, List<String> ids) async {
    try {
      return await _personApiRepository.mergePerson(id, ids: ids);
    } catch (error, stack) {
      _log.severe("Error while updating person name", error, stack);
    }
    return null;
  }
}
