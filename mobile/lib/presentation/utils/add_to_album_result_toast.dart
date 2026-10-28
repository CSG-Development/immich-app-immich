import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

/// Toast plan for an "Add to album" result: which i18n key to show, with which
/// arguments and which [ToastType].
typedef AddToAlbumToastSpec = ({String messageKey, Map<String, Object> args, ToastType toastType});

/// Decides which toast an "Add to album" result deserves.
///
/// Matrix (aligned with `add_action_button.widget.dart` and
/// `favorite_bottom_sheet.widget.dart`, which already did this correctly):
///
/// * `added > 0` -> success "added to album" (partial success is still success)
/// * `added == 0 && failed > 0` -> error "assets cannot be added" (e.g. the
///   server rejected the assets with `no_permission`)
/// * `added == 0 && failed == 0` -> info "already in album"
///
/// Pure: no [BuildContext], no side effects — unit-testable on its own.
AddToAlbumToastSpec resolveAddToAlbumToast({required String albumName, required int added, required int failed}) {
  if (added > 0) {
    return (messageKey: 'add_to_album_bottom_sheet_added', args: {'album': albumName}, toastType: ToastType.success);
  }
  if (failed > 0) {
    return (messageKey: 'assets_cannot_be_added_to_album_count', args: {'count': failed}, toastType: ToastType.error);
  }
  return (
    messageKey: 'add_to_album_bottom_sheet_already_exists',
    args: {'album': albumName},
    toastType: ToastType.info,
  );
}

/// Shows the toast described by [resolveAddToAlbumToast].
void showAddToAlbumResultToast({
  required BuildContext context,
  required String albumName,
  required int added,
  required int failed,
}) {
  final spec = resolveAddToAlbumToast(albumName: albumName, added: added, failed: failed);
  ImmichToast.show(
    context: context,
    msg: spec.messageKey.t(context: context, args: spec.args),
    toastType: spec.toastType,
  );
}
