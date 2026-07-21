import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/repositories/person_api.repository.dart';
import 'package:mocktail/mocktail.dart';
import 'package:openapi/api.dart';

class _MockPeopleApi extends Mock implements PeopleApi {}

void main() {
  late PeopleApi api;
  late PersonApiRepository repository;

  setUpAll(() {
    registerFallbackValue(PersonUpdateDto());
  });

  setUp(() {
    api = _MockPeopleApi();
    repository = PersonApiRepository(api);
  });

  test('update sends and returns the person favorite state', () async {
    when(() => api.updatePerson('person-1', any())).thenAnswer(
      (_) async => PersonResponseDto(
        birthDate: null,
        id: 'person-1',
        isFavorite: true,
        isHidden: false,
        name: 'Person',
        thumbnailPath: '/thumbnail',
      ),
    );

    final person = await repository.update('person-1', isFavorite: true);
    final request = verify(() => api.updatePerson('person-1', captureAny())).captured.single as PersonUpdateDto;

    expect(request.isFavorite, isTrue);
    expect(person.isFavorite, isTrue);
  });
}
