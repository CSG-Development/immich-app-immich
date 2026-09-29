import 'package:cast/session.dart';
import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/store.model.dart';
import 'package:immich_mobile/domain/services/store.service.dart';
import 'package:immich_mobile/entities/store.entity.dart';
import 'package:immich_mobile/infrastructure/repositories/db.repository.dart';
import 'package:immich_mobile/infrastructure/repositories/store.repository.dart';
import 'package:immich_mobile/models/cast/cast_manager_state.dart';
import 'package:immich_mobile/models/sessions/session_create_response.model.dart';
import 'package:immich_mobile/repositories/gcast.repository.dart';
import 'package:immich_mobile/services/gcast.service.dart';
import 'package:mocktail/mocktail.dart';

import '../repository.mocks.dart';
import '../unit/factories/remote_asset_factory.dart';

const endpoint = 'http://localhost:2283/api/v1';

class FakeGCastRepository extends GCastRepository {
  String? sessionId;
  final List<(String, Map<String, dynamic>)> sentMessages = [];

  @override
  String? getSessionId() => sessionId;

  @override
  void sendMessage(String namespace, Map<String, dynamic> message) {
    sentMessages.add((namespace, message));
  }

  List<Map<String, dynamic>> loads() =>
      sentMessages.where((m) => m.$1 == CastSession.kNamespaceMedia && m.$2['type'] == 'LOAD').map((m) => m.$2).toList();
}

SessionCreateResponse validSession() {
  final now = DateTime.now();
  return SessionCreateResponse(
    createdAt: now.toIso8601String(),
    current: true,
    deviceOS: 'Cast',
    deviceType: 'Cast',
    expiresAt: now.add(const Duration(minutes: 15)).toIso8601String(),
    id: 'session-1',
    token: 'tok-1',
    updatedAt: now.toIso8601String(),
  );
}

void main() {
  late Drift db;

  late FakeGCastRepository repo;
  late MockSessionsAPIRepository sessionsApi;
  late MockAssetApiRepository assetApi;
  late GCastService sut;
  late List<String> errors;
  late List<CastState> castStates;

  setUpAll(() async {
    db = Drift(DatabaseConnection(NativeDatabase.memory(), closeStreamsSynchronously: true));
    await StoreService.init(storeRepository: DriftStoreRepository(db), listenUpdates: false);
  });

  tearDownAll(() async {
    await db.close();
  });

  setUp(() async {
    await Store.put(StoreKey.serverEndpoint, endpoint);

    repo = FakeGCastRepository();
    sessionsApi = MockSessionsAPIRepository();
    assetApi = MockAssetApiRepository();
    errors = [];
    castStates = [];

    sut = GCastService(repo, sessionsApi, assetApi)
      ..onCastError = errors.add
      ..onCastState = castStates.add;

    repo.onCastStatus?.call(CastSessionState.connected);
    repo.sessionId = 'receiver-app-session';

    when(() => sessionsApi.createSession(any(), any(), duration: any(named: 'duration')))
        .thenAnswer((_) async => validSession());
    when(() => assetApi.getAssetMIMEType(any())).thenAnswer((_) async => 'image/jpeg');
  });

  group('GCastService.loadMedia', () {
    test('sends a LOAD with a session-scoped thumbnail url for photos', () async {
      final asset = RemoteAssetFactory.create();

      await sut.loadMedia(asset, false);

      final loads = repo.loads();
      expect(loads, hasLength(1));
      expect(
        loads.single['media']['contentUrl'],
        '$endpoint/assets/${asset.id}/thumbnail?size=fullsize&edited=true&sessionKey=tok-1',
      );
      expect(loads.single['media']['contentType'], 'image/jpeg');
      expect(sut.currentAssetId, asset.id);
      expect(errors, isEmpty);
    });

    test('sends a LOAD with a well-formed video playback url', () async {
      when(() => assetApi.getAssetMIMEType(any())).thenAnswer((_) async => 'video/mp4');
      final asset = RemoteAssetFactory.create(type: AssetType.video);

      await sut.loadMedia(asset, false);

      final loads = repo.loads();
      expect(loads, hasLength(1));
      expect(loads.single['media']['contentUrl'], '$endpoint/assets/${asset.id}/video/playback?sessionKey=tok-1');
    });

    test('queues the load until the media application registers, then sends it', () async {
      repo.sessionId = null;
      final asset = RemoteAssetFactory.create();

      await sut.loadMedia(asset, false);
      expect(repo.loads(), isEmpty);

      repo.onCastMessage?.call({
        'type': 'RECEIVER_STATUS',
        'status': {
          'applications': [
            {'appId': 'CC1AD845', 'sessionId': 'app-1', 'transportId': 't-1'},
          ],
        },
      });

      final loads = repo.loads();
      expect(loads, hasLength(1));
      expect(loads.single['media']['contentUrl'], contains('sessionKey=tok-1'));
      expect(errors, isEmpty);
    });

    test('the most recently queued load wins', () async {
      repo.sessionId = null;
      when(() => assetApi.getAssetMIMEType(any())).thenAnswer((_) async => 'video/mp4');
      final photo = RemoteAssetFactory.create();
      final video = RemoteAssetFactory.create(type: AssetType.video);

      await sut.loadMedia(photo, false);
      await sut.loadMedia(video, false);
      expect(repo.loads(), isEmpty);

      repo.onCastMessage?.call({
        'type': 'RECEIVER_STATUS',
        'status': {
          'applications': [
            {'appId': 'CC1AD845', 'sessionId': 'app-1', 'transportId': 't-1'},
          ],
        },
      });

      final loads = repo.loads();
      expect(loads, hasLength(1));
      expect(loads.single['media']['contentUrl'], contains('video/playback'));
    });

    test('reports an error when the mime type cannot be determined', () async {
      when(() => assetApi.getAssetMIMEType(any())).thenAnswer((_) async => null);

      await sut.loadMedia(RemoteAssetFactory.create(), false);

      expect(errors, ['Unable to determine the media type of the asset.']);
      expect(repo.loads(), isEmpty);
    });

    test('reports an error when session creation fails', () async {
      when(() => sessionsApi.createSession(any(), any(), duration: any(named: 'duration'))).thenThrow(Exception('boom'));

      await sut.loadMedia(RemoteAssetFactory.create(), false);

      expect(errors, hasLength(1));
      expect(errors.single, contains('Failed to start casting'));
      expect(repo.loads(), isEmpty);
    });

    test('does not reload the same asset without the reload flag', () async {
      final asset = RemoteAssetFactory.create();

      await sut.loadMedia(asset, false);
      await sut.loadMedia(asset, false);

      expect(repo.loads(), hasLength(1));
    });
  });

  group('GCastService cast messages', () {
    test('surfaces LOAD_FAILED as an idle state and an error', () {
      repo.onCastMessage?.call({'type': 'LOAD_FAILED', 'requestId': 7});

      expect(castStates.last, CastState.idle);
      expect(errors, hasLength(1));
      expect(errors.single, contains('could not load the media'));
    });

    test('a queued load is discarded on LOAD_FAILED', () async {
      repo.sessionId = null;
      final asset = RemoteAssetFactory.create();

      await sut.loadMedia(asset, false);
      repo.onCastMessage?.call({'type': 'LOAD_FAILED', 'requestId': 7});

      repo.onCastMessage?.call({
        'type': 'RECEIVER_STATUS',
        'status': {
          'applications': [
            {'appId': 'CC1AD845', 'sessionId': 'app-1', 'transportId': 't-1'},
          ],
        },
      });

      expect(repo.loads(), isEmpty);
    });

    test('MEDIA_STATUS updates the state without side effects on the connection', () {
      repo.onCastMessage?.call({
        'type': 'MEDIA_STATUS',
        'status': [
          {
            'playerState': 'PLAYING',
            'currentTime': 12.5,
            'media': {
              'duration': 120,
            },
          },
        ],
      });

      expect(castStates.last, CastState.playing);
      expect(errors, isEmpty);
    });
  });
}
