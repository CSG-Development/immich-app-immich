import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/utils/album_access.dart';
import 'package:openapi/api.dart';

void main() {
  ApiException apiError(String message) => ApiException(400, '{"message":"$message"}');

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
