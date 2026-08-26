import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/pages/editing/edit.page.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/base_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/images/image_provider.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';

class EditImageActionButton extends ConsumerWidget {
  const EditImageActionButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentAsset = ref.watch(assetViewerProvider.select((s) => s.currentAsset));

    void onPress() {
      if (currentAsset == null) {
        return;
      }

      final image = Image(image: getFullImageProvider(currentAsset, originalOnly: true));

      context.navigator.push(
        MaterialPageRoute(
          builder: (context) => EditImagePage(asset: currentAsset, image: image, isEdited: false),
        ),
      );
    }

    return BaseActionButton(
      iconData: Icons.tune,
      label: "edit".t(context: context),
      onPressed: onPress,
    );
  }
}
