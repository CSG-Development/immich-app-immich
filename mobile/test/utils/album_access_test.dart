import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/utils/album_access.dart';
import 'package:openapi/api.dart';

void main() {
  ApiException apiError(String message) => ApiException(400, '{"message":"$message"}');

  AlbumResponseDto album({
    List<AlbumUserResponseDto> albumUsers = const [],
  }) {
    return AlbumResponseDto(
      albumName: 'test',
      albumThumbnailAssetId: null,
      albumUsers: albumUsers,
      assetCount: 0,
      createdAt: DateTime(2024),
      description: '',
      hasSharedLink: false,
      id: 'album-id',
      isActivityEnabled: true,
      shared: albumUsers.isNotEmpty,
      updatedAt: DateTime(2024),
    );
  }

  AlbumUserResponseDto albumUser(String id, AlbumUserRole role) {
    return AlbumUserResponseDto(
      role: role,
      user: UserResponseDto(
        avatarColor: UserAvatarColor.primary,
        email: '$id@example.com',
        id: id,
        name: id,
        profileChangedAt: DateTime(2024),
        profileImagePath: '',
      ),
    );
  }

  group('isAlbumEditor', () {
    const ownerId = 'owner-id';
    const editorId = 'editor-id';
    const viewerId = 'viewer-id';

    final shared = album(
      albumUsers: [
        albumUser(editorId, AlbumUserRole.editor),
        albumUser(viewerId, AlbumUserRole.viewer),
      ],
    );

    test('returns true for the album owner', () {
      expect(isAlbumEditor(shared, ownerId, ownerId), isTrue);
      expect(isAlbumEditor(album(), ownerId, ownerId), isTrue);
    });

    test('returns true for editors', () {
      expect(isAlbumEditor(shared, editorId, ownerId), isTrue);
    });

    test('returns false for viewers', () {
      expect(isAlbumEditor(shared, viewerId, ownerId), isFalse);
    });
  });

  group('classifyAlbumAccessError', () {
    test('detects deleted album', () {
      expect(classifyAlbumAccessError(apiError('Album has been deleted')), isA<AlbumEditAccessDeleted>());
      expect(classifyAlbumAccessError(apiError('Album not found')), isA<AlbumEditAccessDeleted>());
    });

    test('defaults to access denied', () {
      expect(
        classifyAlbumAccessError(apiError('Not found or no album.read access')),
        isA<AlbumEditAccessDenied>(),
      );
    });
  });

  group('isAlbumPermissionError', () {
    test('matches known album permission messages', () {
      expect(isAlbumPermissionError(apiError('Not found or no album.read access')), isTrue);
      expect(isAlbumPermissionError(apiError('Not found or no albumAsset.create access')), isTrue);
      expect(isAlbumPermissionError(apiError('Album has been deleted')), isTrue);
      expect(isAlbumPermissionError(apiError('Album not found')), isTrue);
      expect(isAlbumPermissionError(apiError('Something else')), isFalse);
    });
  });

  group('albumAccessMessageKey', () {
    test('maps results to i18n keys', () {
      expect(albumAccessMessageKey(const AlbumEditAccessDenied()), 'album_access_denied');
      expect(albumAccessMessageKey(const AlbumEditAccessDeleted()), 'album_deleted_by_owner');
    });
  });
}
