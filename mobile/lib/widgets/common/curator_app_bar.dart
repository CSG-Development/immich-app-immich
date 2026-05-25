import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/setting.model.dart';
import 'package:immich_mobile/extensions/backup_error_extensions.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/backup/drift_backup.provider.dart';
import 'package:immich_mobile/providers/cast.provider.dart';
import 'package:immich_mobile/providers/infrastructure/setting.provider.dart';
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
    const widgetSize = 30.0;
    final isCasting = ref.watch(castProvider.select((c) => c.isCasting));
    final curatorDevice = ref.watch(deviceProvider);
    final connectionInfo = curatorDevice.deviceFound
        ? ConnectionInfo.fromDebugHostType(curatorDevice.debugHostType, curatorDevice.baseUrl)
        : null;

    buildBackupIndicator() {
      final backupError = ref.watch(driftBackupProvider.select((state) => state.error));
      final hasNetworkWarning = backupError.isNetworkWarning;
      final hasError = backupError.isFailure;
      final indicatorIcon = hasNetworkWarning || hasError
          ? Icon(
              Icons.warning_rounded,
              size: 12,
              color: hasNetworkWarning
                  ? backupError.badgeIconColor(context.colorScheme)
                  : context.colorScheme.error,
              semanticLabel: 'backup_controller_page_backup'.tr(),
            )
          : _getBackupBadgeIcon(context, ref);
      final badgeBackground = hasNetworkWarning
          ? backupError.badgeBackgroundColor(context.colorScheme)
          : hasError
          ? context.colorScheme.errorContainer
          : context.colorScheme.surfaceContainer;

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
      leading: Builder(
        builder: (context) {
          return IconButton(
            icon: const Icon(Icons.menu),
            onPressed: () => context.findRootAncestorStateOfType<ScaffoldState>()?.openDrawer(),
          );
        },
      ),
      title: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          SvgPicture.asset(
            context.isDarkTheme
                ? 'assets/curator-photos-logo-dark.svg'
                : 'assets/curator-photos-logo-light.svg',
            height: 14,
          ),
          if (connectionInfo != null)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text(
                connectionInfo.defaultLabel,
                style: context.textTheme.labelSmall?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
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

  Widget? _getBackupBadgeIcon(BuildContext context, WidgetRef ref) {
    final backupStateStream = ref.watch(settingsProvider).watch(Setting.enableBackup);
    final iconColor = context.isDarkTheme ? Colors.white : Colors.black;
    final isUploading = ref.watch(
      driftBackupProvider.select((state) => state.showsBackupProgress),
    );

    return StreamBuilder(
      stream: backupStateStream,
      initialData: false,
      builder: (ctx, snapshot) {
        final backupEnabled = snapshot.data ?? false;

        if (!backupEnabled) {
          return Icon(
            Icons.cloud_off_rounded,
            size: 9,
            color: iconColor,
            semanticLabel: 'backup_controller_page_backup'.tr(),
          );
        }

        if (isUploading) {
          return Container(
            padding: const EdgeInsets.all(3.5),
            child: CircularProgressIndicator(
              strokeWidth: 2,
              strokeCap: StrokeCap.round,
              valueColor: AlwaysStoppedAnimation<Color>(iconColor),
              semanticsLabel: 'backup_controller_page_backup'.tr(),
            ),
          );
        }

        return Icon(
          Icons.check_outlined,
          size: 9,
          color: iconColor,
          semanticLabel: 'backup_controller_page_backup'.tr(),
        );
      },
    );
  }
}
