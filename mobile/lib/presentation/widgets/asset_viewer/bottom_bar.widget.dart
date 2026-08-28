import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/enums.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/domain/services/timeline.service.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/add_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/copy_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/delete_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/delete_local_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/delete_permanent_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/edit_image_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/restore_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/share_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/action_buttons/upload_action_button.widget.dart';
import 'package:immich_mobile/presentation/widgets/asset_viewer/ocr_toggle_button.widget.dart';
import 'package:immich_mobile/providers/asset_viewer/asset_viewer.provider.dart';
import 'package:immich_mobile/providers/infrastructure/readonly_mode.provider.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/routes.provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/utils/fork_server_version.dart';
import 'package:immich_mobile/widgets/asset_viewer/video_controls.dart';

class ViewerBottomBar extends ConsumerWidget {
  const ViewerBottomBar({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final asset = ref.watch(assetViewerProvider.select((s) => s.currentAsset));
    if (asset == null) {
      return const SizedBox.shrink();
    }

    final isReadonlyModeEnabled = ref.watch(readonlyModeProvider);
    final user = ref.watch(currentUserProvider);
    final isOwner = asset is RemoteAsset && asset.ownerId == user?.id;
    final showingDetails = ref.watch(assetViewerProvider.select((s) => s.showingDetails));
    final isInLockedView = ref.watch(inLockedViewProvider);
    final isInTrash = ref.read(timelineServiceProvider).origin == TimelineOrigin.trash;
    final serverInfo = ref.watch(serverInfoProvider);

    final originalTheme = context.themeData;

    final actions = <Widget>[
      if (asset.isImage) const CopyActionButton(source: ActionSource.viewer),
      if (isInTrash && isOwner && asset.hasRemote)
        const RestoreActionButton(source: ActionSource.viewer)
      else
        const ShareActionButton(source: ActionSource.viewer),

      if (!isInLockedView) ...[
        if (!isInTrash) ...[
          if (asset.isLocalOnly) const UploadActionButton(source: ActionSource.viewer),
          if (asset.isEditable && serverInfo.serverVersion.isAtLeastV1_31) const EditImageActionButton(),
          if (asset.hasRemote) AddActionButton(originalTheme: originalTheme),
        ],
        if (isOwner) ...[
          if (asset.isLocalOnly)
            const DeleteLocalActionButton(source: ActionSource.viewer)
          else if (isInTrash || asset.isTrashed)
            const DeletePermanentActionButton(source: ActionSource.viewer, useShortLabel: true)
          else
            const DeleteActionButton(source: ActionSource.viewer, showConfirmation: true),
        ],
      ],
    ];

    return AnimatedSwitcher(
      duration: Durations.short4,
      child: showingDetails
          ? const SizedBox.shrink()
          : Theme(
              data: context.themeData.copyWith(
                iconTheme: const IconThemeData(size: 22, color: Colors.white),
                textTheme: context.themeData.textTheme.copyWith(
                  labelLarge: context.themeData.textTheme.labelLarge?.copyWith(color: Colors.white),
                ),
              ),
              child: Stack(
                children: [
                  const Positioned.fill(
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(
                          gradient: LinearGradient(
                            begin: Alignment.bottomCenter,
                            end: Alignment.topCenter,
                            colors: [Colors.black45, Colors.black12, Colors.transparent],
                            stops: [0.0, 0.7, 1.0],
                          ),
                        ),
                      ),
                    ),
                  ),
                  SafeArea(
                    top: false,
                    child: Padding(
                      padding: const EdgeInsets.only(top: 16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          if (asset.isImage) OcrToggleButton(asset: asset),
                          if (asset.isVideo) VideoControls(videoPlayerName: asset.heroTag),
                          if (!isReadonlyModeEnabled)
                            SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              padding: const EdgeInsets.symmetric(horizontal: 8),
                              child: Row(mainAxisSize: MainAxisSize.min, children: actions),
                            ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),
    );
  }
}
