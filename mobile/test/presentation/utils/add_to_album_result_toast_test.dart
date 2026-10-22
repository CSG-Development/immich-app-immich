import 'package:flutter_test/flutter_test.dart';
import 'package:immich_mobile/presentation/utils/add_to_album_result_toast.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

void main() {
  const albumName = 'My album';

  group('resolveAddToAlbumToast', () {
    test('some assets were added -> success toast', () {
      final spec = resolveAddToAlbumToast(albumName: albumName, added: 1, failed: 0);

      expect(spec.messageKey, 'add_to_album_bottom_sheet_added');
      expect(spec.args, {'album': albumName});
      expect(spec.toastType, ToastType.success);
    });

    test('nothing added and some rejected -> cannot-be-added error (was wrongly "Already in")', () {
      final spec = resolveAddToAlbumToast(albumName: albumName, added: 0, failed: 1);

      expect(spec.messageKey, 'assets_cannot_be_added_to_album_count');
      expect(spec.args, {'count': 1});
      expect(spec.toastType, ToastType.error);
    });

    test('nothing added and nothing rejected -> already-exists info', () {
      final spec = resolveAddToAlbumToast(albumName: albumName, added: 0, failed: 0);

      expect(spec.messageKey, 'add_to_album_bottom_sheet_already_exists');
      expect(spec.args, {'album': albumName});
      expect(spec.toastType, ToastType.info);
    });

    test('partial success still reports success', () {
      final spec = resolveAddToAlbumToast(albumName: albumName, added: 2, failed: 3);

      expect(spec.messageKey, 'add_to_album_bottom_sheet_added');
      expect(spec.args, {'album': albumName});
      expect(spec.toastType, ToastType.success);
    });

    test('many rejections carry the failed count', () {
      final spec = resolveAddToAlbumToast(albumName: albumName, added: 0, failed: 7);

      expect(spec.messageKey, 'assets_cannot_be_added_to_album_count');
      expect(spec.args, {'count': 7});
      expect(spec.toastType, ToastType.error);
    });
  });
}
