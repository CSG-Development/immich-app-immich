import 'dart:async';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hc_device/hc_device.dart';
import 'package:immich_mobile/domain/services/store.service.dart';
import 'package:immich_mobile/infrastructure/repositories/db.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/settings.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/store.repository.dart';
import 'package:immich_mobile/models/connection_state.model.dart' as conn;
import 'package:immich_mobile/services/auth.service.dart';
import 'package:immich_mobile/services/network/endpoint_resolver.dart';
import 'package:mocktail/mocktail.dart';

import '../repository.mocks.dart';
import '../service.mocks.dart';

class MockHcPathResolver extends Mock implements HcPathResolver {}

class MockHcDeviceEndpointResolver extends Mock implements HcDeviceEndpointResolver {}

class MockDeviceProvider extends Mock implements DeviceProvider {}

void main() {
  late AuthService sut;
  late MockAuthApiRepository authApiRepository;
  late MockAuthRepository authRepository;
  late MockApiService apiService;
  late MockBackgroundSyncManager backgroundSyncManager;
  late MockHcPathResolver hcPathResolver;
  late MockHcDeviceEndpointResolver endpointResolver;
  late MockDeviceProvider deviceProvider;
  late Drift db;

  setUp(() async {
    authApiRepository = MockAuthApiRepository();
    authRepository = MockAuthRepository();
    apiService = MockApiService();
    backgroundSyncManager = MockBackgroundSyncManager();
    hcPathResolver = MockHcPathResolver();
    endpointResolver = MockHcDeviceEndpointResolver();
    deviceProvider = MockDeviceProvider();
    sut = AuthService(
      authApiRepository,
      authRepository,
      apiService,
      backgroundSyncManager,
      hcPathResolver,
      endpointResolver,
      deviceProvider,
    );

    when(() => hcPathResolver.clearPhotosSession()).thenAnswer((_) async {});
    when(() => apiService.clearAccessToken()).thenAnswer((_) async {});
    when(() => apiService.setEndpoint(any())).thenAnswer((_) {});
    when(() => apiService.notifyConnectionState(any())).thenAnswer((_) {});

    registerFallbackValue(Uri());
    registerFallbackValue(const conn.ConnectionState());
  });

  setUpAll(() async {
    WidgetsFlutterBinding.ensureInitialized();
    db = Drift(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    await StoreService.init(storeRepository: DriftStoreRepository(db));
    await SettingsRepository.ensureInitialized(db);
  });

  tearDownAll(() async {
    await db.close();
  });

  group('validateServerUrl', () {
    test('Should resolve HTTP endpoint', () async {
      const testUrl = 'http://ip:2283';
      const resolvedUrl = 'http://ip:2283/api';

      when(() => endpointResolver.resolveAndSetEndpointWithPathType(testUrl)).thenAnswer((_) async => resolvedUrl);
      when(() => apiService.setDeviceInfoHeader()).thenAnswer((_) async => {});

      final result = await sut.validateServerUrl(testUrl);

      expect(result, resolvedUrl);

      verify(() => endpointResolver.resolveAndSetEndpointWithPathType(testUrl)).called(1);
      verify(() => apiService.setDeviceInfoHeader()).called(1);
    });

    test('Should resolve HTTPS endpoint', () async {
      const testUrl = 'https://immich.domain.com';
      const resolvedUrl = 'https://immich.domain.com/api';

      when(() => endpointResolver.resolveAndSetEndpointWithPathType(testUrl)).thenAnswer((_) async => resolvedUrl);
      when(() => apiService.setDeviceInfoHeader()).thenAnswer((_) async => {});

      final result = await sut.validateServerUrl(testUrl);

      expect(result, resolvedUrl);

      verify(() => endpointResolver.resolveAndSetEndpointWithPathType(testUrl)).called(1);
      verify(() => apiService.setDeviceInfoHeader()).called(1);
    });

    test('Should throw error on invalid URL', () async {
      const testUrl = 'invalid-url';

      when(() => endpointResolver.resolveAndSetEndpointWithPathType(testUrl)).thenThrow(Exception('Invalid URL'));

      expect(() async => await sut.validateServerUrl(testUrl), throwsA(isA<Exception>()));

      verify(() => endpointResolver.resolveAndSetEndpointWithPathType(testUrl)).called(1);
      verifyNever(() => apiService.setDeviceInfoHeader());
    });

    test('Should throw error on unreachable server', () async {
      const testUrl = 'https://unreachable.server';

      when(
        () => endpointResolver.resolveAndSetEndpointWithPathType(testUrl),
      ).thenThrow(Exception('Server is not reachable'));

      expect(() async => await sut.validateServerUrl(testUrl), throwsA(isA<Exception>()));

      verify(() => endpointResolver.resolveAndSetEndpointWithPathType(testUrl)).called(1);
      verifyNever(() => apiService.setDeviceInfoHeader());
    });
  });

  group('logout', () {
    test('Should logout user', () async {
      when(() => authApiRepository.logout()).thenAnswer((_) async => {});
      when(() => backgroundSyncManager.cancel()).thenAnswer((_) async => {});
      when(() => authRepository.clearLocalData()).thenAnswer((_) => Future.value(null));
      await sut.logout();

      verify(() => authApiRepository.logout()).called(1);
      verify(() => backgroundSyncManager.cancel()).called(1);
      verify(() => authRepository.clearLocalData()).called(1);
    });

    test('Should clear local data even on server error', () async {
      when(() => authApiRepository.logout()).thenThrow(Exception('Server error'));
      when(() => backgroundSyncManager.cancel()).thenAnswer((_) async => {});
      when(() => authRepository.clearLocalData()).thenAnswer((_) => Future.value(null));
      await sut.logout();

      verify(() => authApiRepository.logout()).called(1);
      verify(() => backgroundSyncManager.cancel()).called(1);
      verify(() => authRepository.clearLocalData()).called(1);
    });

    test('Should clear local data even on server logout timeout', () async {
      when(() => authApiRepository.logout()).thenThrow(
        TimeoutException('Future not completed', const Duration(seconds: 3)),
      );
      when(() => backgroundSyncManager.cancel()).thenAnswer((_) async => {});
      when(() => authRepository.clearLocalData()).thenAnswer((_) => Future.value(null));
      await sut.logout();

      verify(() => authApiRepository.logout()).called(1);
      verify(() => backgroundSyncManager.cancel()).called(1);
      verify(() => authRepository.clearLocalData()).called(1);
    });
  });
}
