import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/person.model.dart';
import 'package:immich_mobile/domain/services/people.service.dart';
import 'package:immich_mobile/infrastructure/repositories/people.repository.dart';
import 'package:immich_mobile/repositories/person_api.repository.dart';
import 'package:mocktail/mocktail.dart';

class _MockPeopleRepository extends Mock implements DriftPeopleRepository {}

class _MockPersonApiRepository extends Mock implements PersonApiRepository {}

void main() {
  late DriftPeopleRepository peopleRepository;
  late PersonApiRepository personApiRepository;
  late DriftPeopleService service;

  setUp(() {
    peopleRepository = _MockPeopleRepository();
    personApiRepository = _MockPersonApiRepository();
    service = DriftPeopleService(peopleRepository, personApiRepository);
  });

  test('updateFavorite updates the server before local state', () async {
    const person = PersonDto(
      id: 'person-1',
      isFavorite: true,
      isHidden: false,
      name: 'Person',
      thumbnailPath: '/thumbnail',
    );
    when(() => personApiRepository.update('person-1', isFavorite: true)).thenAnswer((_) async => person);
    when(() => peopleRepository.updateFavorite('person-1', true)).thenAnswer((_) async => 1);

    final result = await service.updateFavorite('person-1', true);

    expect(result, 1);
    verifyInOrder([
      () => personApiRepository.update('person-1', isFavorite: true),
      () => peopleRepository.updateFavorite('person-1', true),
    ]);
  });

  test('updateFavorite does not change local state when the server update fails', () async {
    when(() => personApiRepository.update('person-1', isFavorite: true)).thenThrow(Exception('server update failed'));

    await expectLater(service.updateFavorite('person-1', true), throwsException);
    verifyNever(() => peopleRepository.updateFavorite(any(), any()));
  });
}
