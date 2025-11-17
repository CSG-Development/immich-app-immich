import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/models/backup/backup_state.model.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/cast.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/asset_viewer/cast_dialog.dart';

class CuratorSliverAppBar extends ConsumerWidget {
  final List<Widget>? actions;
  final bool showUploadButton;
  final bool floating;
  final bool pinned;
  final bool snap;
  final Widget? title;
  final double? expandedHeight;

  const CuratorSliverAppBar({
    super.key,
    this.actions,
    this.showUploadButton = true,
    this.floating = true,
    this.pinned = false,
    this.snap = true,
    this.title,
    this.expandedHeight,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isCasting = ref.watch(castProvider.select((c) => c.isCasting));

    return SliverAppBar(
      floating: floating,
      pinned: pinned,
      snap: snap,
      expandedHeight: expandedHeight,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(5))),
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
      title: title ?? const _CuratorLogo(),
      actions: [
        if (actions != null)
          ...actions!.map((action) => Padding(padding: const EdgeInsets.only(right: 16), child: action)),
        if (kDebugMode || kProfileMode)
          IconButton(
            icon: const Icon(Icons.science_rounded),
            onPressed: () => context.pushRoute(const FeatInDevRoute()),
          ),
        if (isCasting)
          Padding(
            padding: const EdgeInsets.only(right: 12),
            child: IconButton(
              onPressed: () {
                showDialog(context: context, builder: (context) => const CastDialog());
              },
              icon: Icon(isCasting ? Icons.cast_connected_rounded : Icons.cast_rounded),
            ),
          ),
        if (showUploadButton)
          const Padding(padding: EdgeInsets.only(right: 20), child: _BackupIndicator()),
      ],
    );
  }
}

class _CuratorLogo extends StatelessWidget {
  const _CuratorLogo();

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 3.0),
      child: SvgPicture.asset(
        context.isDarkTheme
            ? 'assets/curator-photos-logo-dark.svg'
            : 'assets/curator-photos-logo-light.svg',
        height: 28,
      ),
    );
  }
}

class _BackupIndicator extends ConsumerWidget {
  const _BackupIndicator();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    const widgetSize = 30.0;
    final BackUpState backupState = ref.watch(backupProvider);
    final bool isEnableAutoBackup = backupState.backgroundBackup || backupState.autoBackup;
    final badgeBackground = context.colorScheme.surfaceContainer;
    final isDarkTheme = context.isDarkTheme;
    final iconColor = isDarkTheme ? Colors.white : Colors.black;

    Widget? indicatorIcon() {
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
        } else if (backupState.backupProgress != BackUpProgressEnum.inBackground &&
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

      return null;
    }

    final icon = indicatorIcon();

    return InkWell(
      onTap: () => context.pushRoute(const BackupControllerRoute()),
      borderRadius: const BorderRadius.all(Radius.circular(12)),
      child: Badge(
        label: Container(
          width: widgetSize / 2,
          height: widgetSize / 2,
          decoration: BoxDecoration(
            color: badgeBackground,
            border: Border.all(color: context.colorScheme.outline.withValues(alpha: .3)),
            borderRadius: BorderRadius.circular(widgetSize / 2),
          ),
          child: icon,
        ),
        backgroundColor: Colors.transparent,
        alignment: Alignment.bottomRight,
        isLabelVisible: icon != null,
        offset: const Offset(-2, -12),
        child: Icon(Icons.backup_rounded, size: widgetSize, color: context.primaryColor),
      ),
    );
  }
}


