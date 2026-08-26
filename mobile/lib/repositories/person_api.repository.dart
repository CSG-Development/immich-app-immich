import 'dart:io';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/person.model.dart';
import 'package:immich_mobile/providers/api.provider.dart';
import 'package:immich_mobile/repositories/api.repository.dart';
import 'package:openapi/api.dart';

final personApiRepositoryProvider = Provider((ref) => PersonApiRepository(ref.watch(apiServiceProvider).peopleApi));

class PersonApiRepository extends ApiRepository {
  final PeopleApi _api;

  PersonApiRepository(this._api);

  Future<List<PersonDto>> getAll({String? closestPersonId}) async {
    try {
      final dto = await checkNull(_api.getAllPeople(closestPersonId: closestPersonId));
      return dto.people.map(_toPerson).toList();
    } on ApiException catch (e) {
      // The server returns 404 when closestPersonId is unknown or has no feature photo.
      // Fall back to the default list so merge/search screens are not left empty.
      if (closestPersonId != null && e.code == HttpStatus.notFound) {
        final dto = await checkNull(_api.getAllPeople());
        return dto.people.map(_toPerson).toList();
      }
      rethrow;
    }
  }

  Future<PersonDto> get(String id) async {
    final response = await checkNull(_api.getPerson(id));
    return _toPerson(response);
  }

  Future<PersonDto> update(String id, {String? name, DateTime? birthday, bool? isFavorite}) async {
    final birthdayUtc = birthday == null ? null : DateTime.utc(birthday.year, birthday.month, birthday.day);
    final dto = PersonUpdateDto(
      name: name == null ? const Optional.absent() : Optional.present(name),
      birthDate: birthdayUtc == null ? const Optional.absent() : Optional.present(birthdayUtc),
      isFavorite: isFavorite == null ? const Optional.absent() : Optional.present(isFavorite),
    );
    final response = await checkNull(_api.updatePerson(id, dto));
    return _toPerson(response);
  }

  Future<List<BulkIdResponseDto>> mergePerson(String id, {required List<String> ids}) async {
    final dto = await checkNull(_api.mergePerson(id, MergePersonDto(ids: ids)));
    return dto;
  }

  static PersonDto _toPerson(PersonResponseDto dto) => PersonDto(
    birthDate: dto.birthDate,
    id: dto.id,
    isFavorite: dto.isFavorite.orElse(null) ?? false,
    isHidden: dto.isHidden,
    name: dto.name,
    thumbnailPath: dto.thumbnailPath,
  );
}
