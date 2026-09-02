import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

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

  @override
  Widget build(BuildContext context) {
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
      actions: [
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
      ],
    );
  }
}
