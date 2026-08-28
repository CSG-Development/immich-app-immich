import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/person.model.dart';
import 'package:immich_mobile/repositories/person_api.repository.dart';
import 'package:logging/logging.dart';
import 'package:openapi/api.dart';

final personServiceProvider = Provider.autoDispose<PersonService>(
  (ref) => PersonService(ref.watch(personApiRepositoryProvider)),
);

class PersonService {
  final Logger _log = Logger("PersonService");
  final PersonApiRepository _personApiRepository;
  PersonService(this._personApiRepository);

  Future<List<PersonDto>> getAllPeople({String? closestPersonId}) async {
    try {
      return await _personApiRepository.getAll(closestPersonId: closestPersonId);
    } catch (error, stack) {
      _log.severe("Error while fetching curated people", error, stack);
      rethrow;
    }
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
