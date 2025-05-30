// ignore_for_file: avoid-dynamic

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/interfaces/secure_store.interface.dart';
import 'package:immich_mobile/domain/models/secure_store.model.dart';
import 'package:immich_mobile/domain/services/secure_store.service.dart';
import 'package:mocktail/mocktail.dart';

import '../../infrastructure/repository.mock.dart';

const _kAccessToken = '#ThisIsAToken';

void main() {
  late SecureStoreService sut;
  late ISecureStoreRepository mockStoreRepo;
  late StreamController<SecureStoreUpdateEvent> controller;

  setUp(() async {
    controller = StreamController<SecureStoreUpdateEvent>.broadcast();
    mockStoreRepo = MockSecureStoreRepository();
    // For generics, we need to provide fallback to each concrete type to avoid runtime errors
    registerFallbackValue(SecureStoreKey.accessToken);

    when(() => mockStoreRepo.tryGet(any<SecureStoreKey<dynamic>>()))
        .thenAnswer((invocation) async {
      final key = invocation.positionalArguments.firstOrNull as SecureStoreKey;
      return switch (key) {
        SecureStoreKey.accessToken => _kAccessToken,
        // ignore: avoid-wildcard-cases-with-enums
        _ => null,
      };
    });
    when(() => mockStoreRepo.watchAll()).thenAnswer((_) => controller.stream);

    sut = await SecureStoreService.create(storeRepository: mockStoreRepo);
  });

  tearDown(() async {
    sut.dispose();
    await controller.close();
  });

  group("Store Service Init:", () {
    test('Populates the internal cache on init', () {
      verify(() => mockStoreRepo.tryGet(any<SecureStoreKey<dynamic>>()))
          .called(equals(SecureStoreKey.values.length));
      expect(sut.tryGet(SecureStoreKey.accessToken), _kAccessToken);
    });

    test('Listens to stream of store updates', () async {
      final event =
          SecureStoreUpdateEvent(SecureStoreKey.accessToken, _kAccessToken.toUpperCase());
      controller.add(event);

      await pumpEventQueue();

      verify(() => mockStoreRepo.watchAll()).called(1);
      expect(sut.tryGet(SecureStoreKey.accessToken), _kAccessToken.toUpperCase());
    });
  });

  group('Store Service get:', () {
    test('Returns the stored value for the given key', () {
      expect(sut.get(SecureStoreKey.accessToken), _kAccessToken);
    });
  });

  group('Store Service put:', () {
    setUp(() {
      when(() => mockStoreRepo.insert<String>(any<SecureStoreKey<String>>(), any()))
          .thenAnswer((_) async => true);
    });

    test('Skip insert when value is not modified', () async {
      await sut.put(SecureStoreKey.accessToken, _kAccessToken);
      verifyNever(
        () => mockStoreRepo.insert<String>(SecureStoreKey.accessToken, any()),
      );
    });

    test('Insert value when modified', () async {
      final newAccessToken = _kAccessToken.toUpperCase();
      await sut.put(SecureStoreKey.accessToken, newAccessToken);
      verify(
        () =>
            mockStoreRepo.insert<String>(SecureStoreKey.accessToken, newAccessToken),
      ).called(1);
      expect(sut.tryGet(SecureStoreKey.accessToken), newAccessToken);
    });
  });

  group('Store Service watch:', () {
    late StreamController<String?> valueController;

    setUp(() {
      valueController = StreamController<String?>.broadcast();
      when(() => mockStoreRepo.watch<String>(any<SecureStoreKey<String>>()))
          .thenAnswer((_) => valueController.stream);
    });

    tearDown(() async {
      await valueController.close();
    });

    test('Watches a specific key for changes', () async {
      final stream = sut.watch(SecureStoreKey.accessToken);
      final events = <String?>[
        _kAccessToken,
        _kAccessToken.toUpperCase(),
        null,
        _kAccessToken.toLowerCase(),
      ];

      expectLater(stream, emitsInOrder(events));

      for (final event in events) {
        valueController.add(event);
      }

      await pumpEventQueue();
      verify(() => mockStoreRepo.watch<String>(SecureStoreKey.accessToken)).called(1);
    });
  });

  group('Store Service delete:', () {
    setUp(() {
      when(() => mockStoreRepo.delete<String>(any<SecureStoreKey<String>>()))
          .thenAnswer((_) async => true);
    });

    test('Removes the value from the DB', () async {
      await sut.delete(SecureStoreKey.accessToken);
      verify(() => mockStoreRepo.delete<String>(SecureStoreKey.accessToken))
          .called(1);
    });

    test('Removes the value from the cache', () async {
      await sut.delete(SecureStoreKey.accessToken);
      expect(sut.tryGet(SecureStoreKey.accessToken), isNull);
    });
  });

  group('Store Service clear:', () {
    setUp(() {
      when(() => mockStoreRepo.deleteAll()).thenAnswer((_) async => true);
    });

    test('Clears all values from the store', () async {
      await sut.clear();
      verify(() => mockStoreRepo.deleteAll()).called(1);
      expect(sut.tryGet(SecureStoreKey.accessToken), isNull);
    });
  });
}
