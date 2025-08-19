import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/models/backup/backup_state.model.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/cast.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/asset_viewer/cast_dialog.dart';

class CuratorAppBar extends ConsumerWidget implements PreferredSizeWidget {
  @override
  Size get preferredSize => const Size.fromHeight(64.0);
  final List<Widget>? actions;
  final bool showUploadButton;

  const CuratorAppBar({super.key, this.actions, this.showUploadButton = true});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final BackUpState backupState = ref.watch(backupProvider);
    final bool isEnableAutoBackup =
        backupState.backgroundBackup || backupState.autoBackup;
    final isDarkTheme = context.isDarkTheme;
    const widgetSize = 30.0;
    final isCasting = ref.watch(castProvider.select((c) => c.isCasting));

    getBackupBadgeIcon() {
      final iconColor = isDarkTheme ? Colors.white : Colors.black;

      if (isEnableAutoBackup) {
        if (backupState.backupProgress == BackUpProgressEnum.inProgress) {
          return Container(
            padding: const EdgeInsets.all(3.5),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              strokeCap: StrokeCap.round,
              valueColor: AlwaysStoppedAnimation<Color>(iconColor),
              semanticsLabel: 'backup_controller_page_backup'.tr(),
            ),
          );
        } else if (backupState.backupProgress !=
                BackUpProgressEnum.inBackground &&
            backupState.backupProgress != BackUpProgressEnum.manualInProgress) {
          return Icon(
            Icons.check_outlined,
            size: 9,
            color: iconColor,
            semanticLabel: 'backup_controller_page_backup'.tr(),
          );
        }
      }

      if (!isEnableAutoBackup) {
        return Icon(
          Icons.cloud_off_rounded,
          size: 9,
          color: iconColor,
          semanticLabel: 'backup_controller_page_backup'.tr(),
        );
      }
    }

    buildBackupIndicator() {
      final indicatorIcon = getBackupBadgeIcon();
      final badgeBackground = context.colorScheme.surfaceContainer;

      return InkWell(
        onTap: () => context.pushRoute(const BackupControllerRoute()),
        borderRadius: BorderRadius.circular(12),
        child: Badge(
          label: Container(
            width: widgetSize / 2,
            height: widgetSize / 2,
            decoration: BoxDecoration(
              color: badgeBackground,
              border: Border.all(
                color: context.colorScheme.outline.withValues(alpha: .3),
              ),
              borderRadius: BorderRadius.circular(widgetSize / 2),
            ),
            child: indicatorIcon,
          ),
          backgroundColor: Colors.transparent,
          alignment: Alignment.bottomRight,
          isLabelVisible: indicatorIcon != null,
          offset: const Offset(-2, -12),
          child: Icon(
            Icons.backup_rounded,
            size: widgetSize,
            color: context.primaryColor,
          ),
        ),
      );
    }

    return AppBar(
      backgroundColor: context.themeData.appBarTheme.backgroundColor,
      automaticallyImplyLeading: false,
      centerTitle: false,
      titleSpacing: 0.0,
      leading: IconButton(
        icon: const Icon(Icons.menu),
        onPressed: () {
          Scaffold.of(context).openDrawer();
        },
      ),
      title: SvgPicture.asset(
        context.isDarkTheme
            ? 'assets/curator-photos-logo-dark.svg'
            : 'assets/curator-photos-logo-light.svg',
        height: 28,
      ),
      actions: [
        if (actions != null)
          ...actions!.map(
            (action) => Padding(
              padding: const EdgeInsets.only(right: 16),
              child: action,
            ),
          ),
        if (isCasting)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              onPressed: () {
                showDialog(
                  context: context,
                  builder: (context) => const CastDialog(),
                );
              },
              icon: Icon(
                isCasting ? Icons.cast_connected_rounded : Icons.cast_rounded,
              ),
            ),
          ),
        if (showUploadButton)
          Padding(
            padding: const EdgeInsets.only(right: 20),
            child: buildBackupIndicator(),
          ),
      ],
    );
  }
}
