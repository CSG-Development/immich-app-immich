// ignore_for_file: avoid-dynamic

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/interfaces/secure_store.interface.dart';
import 'package:immich_mobile/domain/models/secure_store.model.dart';
import 'package:immich_mobile/domain/services/secure_store.service.dart';
import 'package:mocktail/mocktail.dart';

import '../../infrastructure/repository.mock.dart';

void main() {
  late SecureStoreService sut;
  late ISecureStoreRepository mockStoreRepo;
  late StreamController<SecureStoreUpdateEvent> controller;

  setUp(() async {
    controller = StreamController<SecureStoreUpdateEvent>.broadcast();
    mockStoreRepo = MockSecureStoreRepository();

    when(() => mockStoreRepo.tryGet(any<SecureStoreKey<dynamic>>()))
        .thenAnswer((invocation) async => null);
    when(() => mockStoreRepo.watchAll()).thenAnswer((_) => controller.stream);

    sut = await SecureStoreService.create(storeRepository: mockStoreRepo);
  });

  tearDown(() async {
    sut.dispose();
    await controller.close();
  });

  group("Store Service Init:", () {
    test('Populates the internal cache on init with empty enum', () {
      verify(() => mockStoreRepo.tryGet(any<SecureStoreKey<dynamic>>()))
          .called(equals(SecureStoreKey.values.length));
      // Since SecureStoreKey.values is empty, no values should be populated
    });

    test('Listens to stream of store updates', () async {
      // Since there are no enum values, we can't test with specific keys
      // Just verify the service initializes properly
      verify(() => mockStoreRepo.watchAll()).called(1);
    });
  });

  group('Store Service clear:', () {
    setUp(() {
      when(() => mockStoreRepo.deleteAll()).thenAnswer((_) async => true);
    });

    test('Clears all values from the store', () async {
      await sut.clear();
      verify(() => mockStoreRepo.deleteAll()).called(1);
    });
  });
}

