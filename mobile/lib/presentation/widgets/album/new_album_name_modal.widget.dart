import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/pages/security/widgets/lock_utils.dart';

class NewAlbumNameModal extends StatefulWidget {
  const NewAlbumNameModal({super.key});

  @override
  State<NewAlbumNameModal> createState() => _NewAlbumNameModalState();
}

class _NewAlbumNameModalState extends State<NewAlbumNameModal> {
  late final TextEditingController nameController;
  bool _canCreate = true;

  @override
  void initState() {
    super.initState();
    nameController = TextEditingController(text: 'untitled_album'.tr());
    nameController.addListener(_onNameChanged);
  }

  void _onNameChanged() {
    final canCreate = nameController.text.trim().isNotEmpty;
    if (canCreate != _canCreate) {
      setState(() => _canCreate = canCreate);
    }
  }

  @override
  void dispose() {
    nameController.dispose();
    super.dispose();
  }

  List<Widget> _buildActions(BuildContext context) {
    return [
      TextButton(
        onPressed: () => context.pop(null),
        child: Text(
          "cancel",
          style: TextStyle(color: Colors.red[300], fontWeight: FontWeight.bold),
        ).tr(),
      ),
      TextButton(
        onPressed: _canCreate
            ? () {
                context.pop(nameController.text.trim());
              }
            : null,
        child: Text(
          "create_album",
          style: TextStyle(
            color: _canCreate ? context.primaryColor : context.colorScheme.onSurface.withValues(alpha: 0.38),
            fontWeight: FontWeight.bold,
          ),
        ).tr(),
      ),
    ];
  }

  @override
  Widget build(BuildContext context) {
    final mediaQuery = MediaQuery.of(context);
    final useLandscapePhoneLayout = isLandscapePhone(context);

    if (useLandscapePhoneLayout) {
      // Pin to the top with fixed insets. Do not fold viewInsets into
      // padding/constraints: that re-centers or shrinks the route and
      // pushes the dialog off-screen.
      final keyboardHeight = mediaQuery.viewInsets.bottom;
      const verticalChrome = 52.0; // top inset + dialog vertical padding
      final maxScrollHeight = (mediaQuery.size.height - mediaQuery.padding.top - keyboardHeight - verticalChrome)
          .clamp(120.0, mediaQuery.size.height);
      final dialogWidth = (mediaQuery.size.width - mediaQuery.padding.horizontal - 48).clamp(280.0, 400.0);

      final landscapeDialog = Dialog(
        alignment: Alignment.topCenter,
        insetPadding: EdgeInsets.fromLTRB(
          24 + mediaQuery.padding.left,
          mediaQuery.padding.top + 8,
          24 + mediaQuery.padding.right,
          16,
        ),
        child: SizedBox(
          width: dialogWidth,
          child: ConstrainedBox(
            constraints: BoxConstraints(maxHeight: maxScrollHeight),
            child: SingleChildScrollView(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 12),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text("album_name", style: TextStyle(fontWeight: FontWeight.bold)).tr(),
                    const SizedBox(height: 12),
                    TextFormField(
                      controller: nameController,
                      textCapitalization: TextCapitalization.words,
                      autofocus: true,
                      decoration: InputDecoration(hintText: 'name'.tr(), border: const OutlineInputBorder()),
                    ),
                    const SizedBox(height: 12),
                    Align(
                      alignment: Alignment.centerRight,
                      child: Wrap(spacing: 8, children: _buildActions(context)),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );

      return MediaQuery.removeViewInsets(
        context: context,
        removeBottom: true,
        child: landscapeDialog,
      );
    }

    return AlertDialog(
      title: const Text("album_name", style: TextStyle(fontWeight: FontWeight.bold)).tr(),
      content: SingleChildScrollView(
        child: TextFormField(
          controller: nameController,
          textCapitalization: TextCapitalization.words,
          autofocus: true,
          decoration: InputDecoration(hintText: 'name'.tr(), border: const OutlineInputBorder()),
        ),
      ),
      actions: _buildActions(context),
    );
  }
}
