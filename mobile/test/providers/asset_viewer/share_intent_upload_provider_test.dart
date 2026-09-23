import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/models/auth/auth_state.model.dart';
import 'package:immich_mobile/models/upload/share_intent_attachment.model.dart';
import 'package:immich_mobile/providers/asset_viewer/share_intent_upload.provider.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/infrastructure/asset.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/auth.service.dart';
import 'package:immich_mobile/services/foreground_upload.service.dart';
import 'package:immich_mobile/services/secure_storage.service.dart';
import 'package:immich_mobile/services/share_intent_service.dart';
import 'package:immich_mobile/services/widget.service.dart';
import 'package:immich_mobile/infrastructure/repositories/remote_asset.repository.dart';
import 'package:mocktail/mocktail.dart';

import '../../service.mocks.dart';

class _MockAppRouter extends Mock implements AppRouter {}

class _MockShareIntentService extends Mock implements ShareIntentService {}

class _MockAuthService extends Mock implements AuthService {}

class _MockSecureStorageService extends Mock implements SecureStorageService {}

class _MockWidgetService extends Mock implements WidgetService {}

class _TestAuthNotifier extends AuthNotifier {
  _TestAuthNotifier(Ref ref, AuthState initial)
    : super(
        ref,
        _MockAuthService(),
        MockApiService(),
        MockUserService(),
        _MockSecureStorageService(),
        _MockWidgetService(),
      ) {
    state = initial;
  }
}

void main() {
  late ProviderContainer container;
  late MockForegroundUploadService uploadService;
  late MockRemoteAssetRepository remoteRepository;
  late Directory tempDir;

  const userId = 'user-1';

  String sha1Base64Of(List<int> bytes) {
    return base64Encode(sha1.convert(bytes).bytes);
  }

  File createFile(String name, List<int> bytes) {
    final file = File('${tempDir.path}/$name');
    file.writeAsBytesSync(bytes);
    return file;
  }

  ShareIntentAttachment attachmentFor(File file) {
    return ShareIntentAttachment(path: file.path, type: ShareIntentAttachmentType.image, status: UploadStatus.enqueued);
  }

  setUpAll(() {
    registerFallbackValue(<File>[]);
    registerFallbackValue((String a, int b, int c) {});
    registerFallbackValue((String a, String b) {});
  });

  setUp(() {
    tempDir = Directory.systemTemp.createTempSync('share_intent_upload_test');
    uploadService = MockForegroundUploadService();
    remoteRepository = MockRemoteAssetRepository();

    when(
      () => uploadService.uploadShareIntent(
        any(),
        onProgress: any(named: 'onProgress'),
        onSuccess: any(named: 'onSuccess'),
        onError: any(named: 'onError'),
      ),
    ).thenAnswer((_) async {});

    container = ProviderContainer(
      overrides: [
        appRouterProvider.overrideWithValue(_MockAppRouter()),
        foregroundUploadServiceProvider.overrideWithValue(uploadService),
        shareIntentServiceProvider.overrideWithValue(_MockShareIntentService()),
        remoteAssetRepositoryProvider.overrideWithValue(remoteRepository),
        authProvider.overrideWith(
          (ref) => _TestAuthNotifier(
            ref,
            const AuthState(
              deviceId: 'device-1',
              userId: userId,
              userEmail: 'user@example.com',
              isAuthenticated: true,
              name: 'User',
              isAdmin: false,
              profileImagePath: '',
            ),
          ),
        ),
      ],
    );
    addTearDown(container.dispose);
  });

  tearDown(() {
    tempDir.deleteSync(recursive: true);
  });

  group('uploadAll duplicate pre-check', () {
    test('skips file that is already on the server for the current user', () async {
      final dupBytes = utf8.encode('already uploaded bytes');
      final dupFile = createFile('dup.jpg', dupBytes);
      final dupChecksum = sha1Base64Of(dupBytes);
      when(
        () => remoteRepository.existsByChecksumAndOwner(any(), any()),
      ).thenAnswer((invocation) async => invocation.positionalArguments[0] == dupChecksum);

      container.read(shareIntentUploadProvider.notifier).addAttachments([attachmentFor(dupFile)]);

      final alreadyUploaded = await container.read(shareIntentUploadProvider.notifier).uploadAll([dupFile]);

      expect(alreadyUploaded, 1);
      expect(container.read(shareIntentUploadProvider).single.status, UploadStatus.alreadyUploaded);
      expect(container.read(shareIntentUploadProvider).single.uploadProgress, 1.0);
      verify(() => remoteRepository.existsByChecksumAndOwner(dupChecksum, userId)).called(1);
      verifyNever(
        () => uploadService.uploadShareIntent(
          any(),
          onProgress: any(named: 'onProgress'),
          onSuccess: any(named: 'onSuccess'),
          onError: any(named: 'onError'),
        ),
      );
    });

    test('uploads file whose checksum belongs to another user', () async {
      final bytes = utf8.encode('shared content');
      final file = createFile('foreign.jpg', bytes);
      final checksum = sha1Base64Of(bytes);
      when(
        () => remoteRepository.existsByChecksumAndOwner(any(), any()),
      ).thenAnswer((invocation) async => invocation.positionalArguments[1] != userId);

      container.read(shareIntentUploadProvider.notifier).addAttachments([attachmentFor(file)]);

      final alreadyUploaded = await container.read(shareIntentUploadProvider.notifier).uploadAll([file]);

      expect(alreadyUploaded, 0);
      verify(() => remoteRepository.existsByChecksumAndOwner(checksum, userId)).called(1);
      final uploaded =
          verify(
                () => uploadService.uploadShareIntent(
                  captureAny(),
                  onProgress: any(named: 'onProgress'),
                  onSuccess: any(named: 'onSuccess'),
                  onError: any(named: 'onError'),
                ),
              ).captured.single
              as List<File>;
      expect(uploaded, [file]);
    });

    test('uploads a new file as before', () async {
      final bytes = utf8.encode('brand new content');
      final file = createFile('fresh.jpg', bytes);
      when(() => remoteRepository.existsByChecksumAndOwner(any(), any())).thenAnswer((_) async => false);

      container.read(shareIntentUploadProvider.notifier).addAttachments([attachmentFor(file)]);

      final alreadyUploaded = await container.read(shareIntentUploadProvider.notifier).uploadAll([file]);

      expect(alreadyUploaded, 0);
      expect(container.read(shareIntentUploadProvider).single.status, UploadStatus.running);
      final uploaded =
          verify(
                () => uploadService.uploadShareIntent(
                  captureAny(),
                  onProgress: any(named: 'onProgress'),
                  onSuccess: any(named: 'onSuccess'),
                  onError: any(named: 'onError'),
                ),
              ).captured.single
              as List<File>;
      expect(uploaded, [file]);
    });

    test('falls back to uploading when the pre-check fails (missing file)', () async {
      final missingFile = File('${tempDir.path}/missing.jpg');
      when(() => remoteRepository.existsByChecksumAndOwner(any(), any())).thenAnswer((_) async => false);

      container.read(shareIntentUploadProvider.notifier).addAttachments([attachmentFor(missingFile)]);

      final alreadyUploaded = await container.read(shareIntentUploadProvider.notifier).uploadAll([missingFile]);

      expect(alreadyUploaded, 0);
      final uploaded =
          verify(
                () => uploadService.uploadShareIntent(
                  captureAny(),
                  onProgress: any(named: 'onProgress'),
                  onSuccess: any(named: 'onSuccess'),
                  onError: any(named: 'onError'),
                ),
              ).captured.single
              as List<File>;
      expect(uploaded, [missingFile]);
    });

    test('skips only duplicates and uploads the rest in one batch', () async {
      final dupBytes = utf8.encode('duplicate');
      final freshBytes = utf8.encode('fresh');
      final dupFile = createFile('dup.jpg', dupBytes);
      final freshFile = createFile('fresh.jpg', freshBytes);
      final dupChecksum = sha1Base64Of(dupBytes);
      when(
        () => remoteRepository.existsByChecksumAndOwner(any(), any()),
      ).thenAnswer((invocation) async => invocation.positionalArguments[0] == dupChecksum);

      container.read(shareIntentUploadProvider.notifier).addAttachments([
        attachmentFor(dupFile),
        attachmentFor(freshFile),
      ]);

      final alreadyUploaded = await container.read(shareIntentUploadProvider.notifier).uploadAll([dupFile, freshFile]);

      expect(alreadyUploaded, 1);
      final state = container.read(shareIntentUploadProvider);
      expect(state.firstWhere((a) => a.path == dupFile.path).status, UploadStatus.alreadyUploaded);
      expect(state.firstWhere((a) => a.path == freshFile.path).status, UploadStatus.running);
      final uploaded =
          verify(
                () => uploadService.uploadShareIntent(
                  captureAny(),
                  onProgress: any(named: 'onProgress'),
                  onSuccess: any(named: 'onSuccess'),
                  onError: any(named: 'onError'),
                ),
              ).captured.single
              as List<File>;
      expect(uploaded, [freshFile]);
    });
  });
}

class MockRemoteAssetRepository extends Mock implements RemoteAssetRepository {}
