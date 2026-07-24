import 'package:drift/drift.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/infrastructure/entities/asset_face.entity.drift.dart';
import 'package:immich_mobile/infrastructure/entities/person.entity.drift.dart';
import 'package:immich_mobile/infrastructure/repositories/people.repository.dart';

import '../../medium/repository_context.dart';

void main() {
  late MediumRepositoryContext context;
  late DriftPeopleRepository repository;

  setUp(() {
    context = MediumRepositoryContext();
    repository = DriftPeopleRepository(context.db);
  });

  tearDown(() => context.dispose());

  Future<void> insertPersonWithFace({
    required String personId,
    required String ownerId,
    required bool isFavorite,
  }) async {
    await context.db
        .into(context.db.personEntity)
        .insert(
          PersonEntityCompanion.insert(
            id: personId,
            ownerId: ownerId,
            name: personId,
            isFavorite: isFavorite,
            isHidden: false,
          ),
        );
    final asset = await context.newRemoteAsset(id: 'asset-$personId', ownerId: ownerId);
    await context.db
        .into(context.db.assetFaceEntity)
        .insert(
          AssetFaceEntityCompanion.insert(
            id: 'face-$personId',
            assetId: asset.id,
            personId: Value(personId),
            imageWidth: 100,
            imageHeight: 100,
            boundingBoxX1: 0,
            boundingBoxY1: 0,
            boundingBoxX2: 50,
            boundingBoxY2: 50,
            sourceType: 'machine-learning',
          ),
        );
  }

  test('updateFavorite persists the new state', () async {
    final user = await context.newUser(id: 'owner');
    await insertPersonWithFace(personId: 'person-1', ownerId: user.id, isFavorite: false);

    expect(await repository.updateFavorite('person-1', true), 1);
    expect((await repository.get('person-1'))?.isFavorite, isTrue);
  });

  test('getAllPeople sorts favorite people first', () async {
    final user = await context.newUser(id: 'owner');
    await insertPersonWithFace(personId: 'regular', ownerId: user.id, isFavorite: false);
    await insertPersonWithFace(personId: 'favorite', ownerId: user.id, isFavorite: true);

    final people = await repository.getAllPeople();

    expect(people.map((person) => person.id), ['favorite', 'regular']);
  });
}
