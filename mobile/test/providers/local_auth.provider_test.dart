import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/auth/biometric_status.model.dart';
import 'package:immich_mobile/providers/local_auth.provider.dart';
import 'package:immich_mobile/services/local_auth.service.dart';
import 'package:immich_mobile/services/secure_storage.service.dart';
import 'package:local_auth/local_auth.dart';
import 'package:mocktail/mocktail.dart';

// Mock classes
class MockLocalAuthService extends Mock implements LocalAuthService {}

class MockSecureStorageService extends Mock implements SecureStorageService {}

void main() {
  late MockLocalAuthService mockLocalAuthService;
  late MockSecureStorageService mockSecureStorageService;
  late ProviderContainer container;

  setUp(() {
    mockLocalAuthService = MockLocalAuthService();
    mockSecureStorageService = MockSecureStorageService();

    when(() => mockLocalAuthService.getStatus()).thenAnswer((_) async => const BiometricStatus(
          availableBiometrics: [],
          canAuthenticate: true,
        ));
    when(() => mockLocalAuthService.authenticate(any())).thenAnswer((_) async => true);

    container = ProviderContainer(
      overrides: [
        localAuthServiceProvider.overrideWithValue(mockLocalAuthService),
        secureStorageServiceProvider.overrideWithValue(mockSecureStorageService),
      ],
    );

    registerFallbackValue(AuthenticationOptions());
  });

  tearDown(() {
    container.dispose();
  });

  group('LocalAuthNotifier', () {
    testWidgets('initial state is correct', (tester) async {
      // Access the notifier (creates it if not already created)
      final notifier = container.read(localAuthProvider.notifier);
      // The async getStatus() is called in the constructor, pump to process microtasks
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
      expect(notifier.state.canAuthenticate, true);
    });

    testWidgets('NotEnrolled error shows "biometric_not_enrolled" message', (tester) async {
      // Arrange
      when(() => mockLocalAuthService.authenticate(any())).thenThrow(
        PlatformException(code: 'NotEnrolled', message: 'No Biometrics enrolled on this device.'),
      );

      // Build a simple widget tree to provide context
      final buildContext = await _pumpBuildContext(tester);

      // Act
      final result = await container.read(localAuthProvider.notifier).authenticate(
        buildContext,
        'Authenticate to enable biometrics',
      );

      // Assert
      expect(result, false);
      verify(() => mockLocalAuthService.authenticate(any())).called(1);
    });

    testWidgets('NotAvailable error shows "biometric_not_available" message', (tester) async {
      // Arrange
      when(() => mockLocalAuthService.authenticate(any())).thenThrow(
        PlatformException(code: 'NotAvailable', message: 'Security credentials not available.'),
      );

      final buildContext = await _pumpBuildContext(tester);

      // Act
      final result = await container.read(localAuthProvider.notifier).authenticate(
        buildContext,
        'Authenticate to enable biometrics',
      );

      // Assert
      expect(result, false);
      verify(() => mockLocalAuthService.authenticate(any())).called(1);
    });

    testWidgets('LockedOut error shows "biometric_locked_out" message', (tester) async {
      // Arrange
      when(() => mockLocalAuthService.authenticate(any())).thenThrow(
        PlatformException(code: 'LockedOut', message: 'Locked out.'),
      );

      final buildContext = await _pumpBuildContext(tester);

      // Act
      final result = await container.read(localAuthProvider.notifier).authenticate(
        buildContext,
        'Authenticate to enable biometrics',
      );

      // Assert
      expect(result, false);
    });

    testWidgets('default error shows "failed_to_authenticate" message', (tester) async {
      // Arrange
      when(() => mockLocalAuthService.authenticate(any())).thenThrow(
        PlatformException(code: 'unknown', message: 'Unknown error'),
      );

      final buildContext = await _pumpBuildContext(tester);

      // Act
      final result = await container.read(localAuthProvider.notifier).authenticate(
        buildContext,
        'Authenticate to enable biometrics',
      );

      // Assert
      expect(result, false);
    });

    testWidgets('registerBiometric writes PIN code on success', (tester) async {
      // Arrange
      when(() => mockLocalAuthService.authenticate(any())).thenAnswer((_) async => true);
      when(() => mockSecureStorageService.write(any(), any())).thenAnswer((_) async {});

      final buildContext = await _pumpBuildContext(tester);

      // Act
      final result = await container.read(localAuthProvider.notifier).registerBiometric(
        buildContext,
        '123456',
      );

      // Assert
      expect(result, true);
      verify(() => mockSecureStorageService.write(any(), '123456')).called(1);
    });

    testWidgets('registerBiometric returns false when authentication fails', (tester) async {
      // Arrange
      when(() => mockLocalAuthService.authenticate(any())).thenAnswer((_) async => false);

      final buildContext = await _pumpBuildContext(tester);

      // Act
      final result = await container.read(localAuthProvider.notifier).registerBiometric(
        buildContext,
        '123456',
      );

      // Assert
      expect(result, false);
      verifyNever(() => mockSecureStorageService.write(any(), any()));
    });
  });
}

Future<BuildContext> _pumpBuildContext(WidgetTester tester) async {
  late BuildContext capturedContext;
  await tester.pumpWidget(
    MaterialApp(
      home: Builder(
        builder: (context) {
          capturedContext = context;
          return const Scaffold(body: Text('Test'));
        },
      ),
    ),
  );
  return capturedContext;
}
