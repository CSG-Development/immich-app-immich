import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/models/backup/backup_state.model.dart';
import 'package:immich_mobile/providers/asset.provider.dart';
import 'package:immich_mobile/providers/asset_viewer/scroll_notifier.provider.dart';
import 'package:immich_mobile/providers/auth.provider.dart';
import 'package:immich_mobile/providers/backup/backup.provider.dart';
import 'package:immich_mobile/providers/backup/manual_upload.provider.dart';
import 'package:immich_mobile/providers/locale_provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/providers/websocket.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/bytes_units.dart';
import 'package:immich_mobile/widgets/common/app_bar_dialog/drawer_profile_info.dart';
import 'package:immich_mobile/widgets/common/app_bar_dialog/drawer_server_info.dart';
import 'package:immich_mobile/widgets/common/confirm_dialog.dart';

class CuratorAppBarDrawer extends HookConsumerWidget {
  const CuratorAppBarDrawer({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    BackUpState backupState = ref.watch(backupProvider);
    final theme = context.themeData;
    final user = ref.watch(currentUserProvider);
    final isLoggingOut = useState(false);

    useEffect(
      () {
        ref.read(backupProvider.notifier).updateDiskInfo();
        ref.read(currentUserProvider.notifier).refresh();
        return null;
      },
      [],
    );

    Widget buildActionButton(
      IconData icon,
      String text,
      Function() onTap, {
      Widget? trailing,
    }) {
      return ListTile(
        leading: Icon(
          icon,
          color: theme.textTheme.labelLarge?.color?.withAlpha(250),
        ),
        title: Text(text).tr(),
        onTap: onTap,
        trailing: trailing,
      );
    }

    Widget buildSettingButton() {
      return buildActionButton(
        Icons.settings_outlined,
        "settings",
        () {
          context.pop();
          context.pushRoute(const SettingsRoute());
        },
      );
    }

    Widget buildSignOutButton() {
      return buildActionButton(
        Icons.logout_rounded,
        "sign_out",
        () async {
          if (isLoggingOut.value) {
            return;
          }

          showDialog(
            context: context,
            builder: (BuildContext ctx) {
              return ConfirmDialog(
                title: "app_bar_signout_dialog_title",
                content: "app_bar_signout_dialog_content",
                ok: "yes",
                onOk: () async {
                  isLoggingOut.value = true;
                  await ref
                      .read(authProvider.notifier)
                      .logout()
                      .whenComplete(() => isLoggingOut.value = false);

                  ref.read(manualUploadProvider.notifier).cancelBackup();
                  ref.read(backupProvider.notifier).cancelBackup();
                  ref.read(assetProvider.notifier).clearAllAssets();
                  ref.read(websocketProvider.notifier).disconnect();
                  context.replaceRoute(const LoginRoute());
                },
              );
            },
          );
        },
        trailing: isLoggingOut.value
            ? const SizedBox.square(
                dimension: 20,
                child: CircularProgressIndicator(strokeWidth: 2),
              )
            : null,
      );
    }

    Widget buildStorageInformation() {
      var percentage = backupState.serverInfo.diskUsagePercentage / 100;
      var usedDiskSpace = backupState.serverInfo.diskUse;
      var totalDiskSpace = backupState.serverInfo.diskSize;

      if (user != null && user.hasQuota) {
        usedDiskSpace = formatBytes(user.quotaUsageInBytes);
        totalDiskSpace = formatBytes(user.quotaSizeInBytes);
        percentage = user.quotaUsageInBytes / user.quotaSizeInBytes;
      }

      return Container(
        padding: const EdgeInsets.all(16.0),
        decoration: BoxDecoration(
          color: context.colorScheme.surfaceContainerLowest,
          borderRadius: const BorderRadius.only(
            topLeft: Radius.circular(8.0),
            topRight: Radius.circular(8.0),
          ),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Text(
                  "backup_controller_page_server_storage",
                  style: context.textTheme.labelLarge?.copyWith(
                    fontSize: 16.0,
                    color: context.textTheme.bodySmall?.color
                        ?.withValues(alpha: 0.87),
                  ),
                ).tr(),
                Icon(
                  Icons.storage_rounded,
                  color: theme.primaryColor,
                  size: 24.0,
                ),
              ],
            ),
            const SizedBox(height: 4.0),
            Text(
              'backup_controller_page_storage_format',
              style: TextStyle(
                fontSize: 16.0,
                color: context.isDarkTheme
                    ? const Color(0xFFB2B2B2)
                    : const Color(0xFF7A7A7A),
              ),
            ).tr(
              namedArgs: {
                'used': usedDiskSpace,
                'total': totalDiskSpace,
              },
            ),
            const SizedBox(height: 4.0),
            LinearProgressIndicator(
              minHeight: 8.0,
              value: percentage,
              borderRadius: const BorderRadius.all(
                Radius.circular(10.0),
              ),
              stopIndicatorColor: Colors.transparent,
              trackGap: 0,
            ),
          ],
        ),
      );
    }

    Widget drawerContent = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          decoration: BoxDecoration(
            color: context.colorScheme.surfaceContainerLowest,
          ),
          padding: const EdgeInsets.only(
            top: 10.0,
            bottom: 24.0,
            left: 16.0,
            right: 16,
          ),
          child: SafeArea(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                SvgPicture.asset(
                  context.isDarkTheme
                      ? 'assets/curator-photos-logo-dark.svg'
                      : 'assets/curator-photos-logo-light.svg',
                  height: 32,
                ),
                const SizedBox(height: 12),
                const DrawerProfileInfoBox(),
              ],
            ),
          ),
        ),
        buildSettingButton(),
        buildSignOutButton(),
        Expanded(
          child: Padding(
            padding: const EdgeInsets.only(
              left: 16.0,
              right: 16.0,
              bottom: 12.0,
            ),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                buildStorageInformation(),
                const SizedBox(height: 4.0),
                const DrawerServerInfo(),
              ],
            ),
          ),
        ),
      ],
    );

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Drawer(
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.zero),
      child: SafeArea(
        child: Container(
          decoration:
              BoxDecoration(color: context.colorScheme.surfaceContainer),
          child: isLandscape
              ? SingleChildScrollView(
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: MediaQuery.of(context).size.height,
                    ),
                    child: IntrinsicHeight(
                      child: drawerContent,
                    ),
                  ),
                )
              : drawerContent,
        ),
      ),
    );
  }
}
