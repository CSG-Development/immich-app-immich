import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/providers/infrastructure/action.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';

/// Inline, editable asset description shown in the asset details Overview tab.
class SheetAssetDescription extends ConsumerStatefulWidget {
  final BaseAsset asset;
  final ExifInfo? exifInfo;

  const SheetAssetDescription({super.key, required this.asset, this.exifInfo});

  @override
  ConsumerState<SheetAssetDescription> createState() => _SheetAssetDescriptionState();
}

class _SheetAssetDescriptionState extends ConsumerState<SheetAssetDescription> {
  late final TextEditingController _controller;
  final _descriptionFocus = FocusNode();
  bool _isSaving = false;
  late String _lastSavedDescription;

  @override
  void initState() {
    super.initState();
    final initialDescription = widget.exifInfo?.description ?? '';
    _controller = TextEditingController(text: initialDescription);
    _lastSavedDescription = initialDescription;
    // Save whenever editing ends, regardless of how focus is lost
    // (keyboard dismissed, tab switched, tap elsewhere, or Done pressed).
    _descriptionFocus.addListener(_onFocusChanged);
  }

  @override
  void dispose() {
    _descriptionFocus.removeListener(_onFocusChanged);
    _descriptionFocus.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _onFocusChanged() {
    if (!_descriptionFocus.hasFocus) {
      saveDescription();
    }
  }

  bool get _isOwner {
    final user = ref.read(currentUserProvider);
    final asset = widget.asset;
    return user != null && asset is RemoteAsset && asset.ownerId == user.id;
  }

  Future<void> saveDescription() async {
    if (_isSaving) {
      return;
    }

    final newDescription = _controller.text.trim();

    // Compare against the last value we actually persisted (not the possibly
    // stale exif snapshot) so that the several focus-loss / tap-outside /
    // Done triggers that fire together result in a single save.
    if (newDescription == _lastSavedDescription) {
      _descriptionFocus.unfocus();
      return;
    }

    _isSaving = true;
    try {
      final editAction =
          await ref.read(actionProvider.notifier).updateDescription(ActionSource.viewer, newDescription);

      if (!mounted) {
        return;
      }

      if (editAction.success) {
        _lastSavedDescription = newDescription;
      } else {
        _controller.text = _lastSavedDescription;
        ImmichToast.show(
          context: context,
          msg: 'exif_bottom_sheet_description_error'.t(context: context),
          toastType: ToastType.error,
        );
      }
    } finally {
      _isSaving = false;
    }

    if (mounted) {
      _descriptionFocus.unfocus();
    }
  }

  @override
  Widget build(BuildContext context) {
    final isOwner = _isOwner;
    final exifInfo = widget.exifInfo;
    final hintText = (isOwner ? 'exif_bottom_sheet_description' : 'exif_bottom_sheet_no_description').t(
      context: context,
    );

    // Re-sync with the latest backend value whenever we are not actively
    // editing. Skip while exifInfo itself is null (provider reload after
    // invalidate) so we do not wipe the field mid-refresh.
    if (exifInfo != null && !_descriptionFocus.hasFocus) {
      final currentDescription = exifInfo.description ?? '';
      if (_controller.text != currentDescription) {
        _controller.text = currentDescription;
        _lastSavedDescription = currentDescription;
      }
    }

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8),
      child: IgnorePointer(
        ignoring: !isOwner,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                keyboardType: TextInputType.multiline,
                maxLines: null,
                focusNode: _descriptionFocus,
                onTapOutside: (_) => saveDescription(),
                decoration: InputDecoration(
                  hintText: hintText,
                  border: InputBorder.none,
                  enabledBorder: InputBorder.none,
                  focusedBorder: InputBorder.none,
                  disabledBorder: InputBorder.none,
                  errorBorder: InputBorder.none,
                  focusedErrorBorder: InputBorder.none,
                ),
              ),
            ),
            // Explicit "Done" affordance while editing, so users do not have
            // to rely on dismissing the keyboard to confirm the input.
            AnimatedBuilder(
              animation: _descriptionFocus,
              builder: (context, _) {
                if (!_descriptionFocus.hasFocus) {
                  return const SizedBox.shrink();
                }
                return Padding(
                  padding: const EdgeInsets.only(left: 8.0),
                  child: TextButton(
                    onPressed: saveDescription,
                    child: Text('done'.t(context: context)),
                  ),
                );
              },
            ),
          ],
        ),
      ),
    );
  }
}
