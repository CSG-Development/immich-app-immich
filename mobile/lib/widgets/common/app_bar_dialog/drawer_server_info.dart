import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart' hide Store;
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/models/server_info/server_info.model.dart';
import 'package:immich_mobile/providers/locale_provider.dart';
import 'package:immich_mobile/providers/server_info.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:immich_mobile/widgets/common/app_bar_dialog/server_update_notification.dart';
import 'package:package_info_plus/package_info_plus.dart';

class DrawerServerInfo extends HookConsumerWidget {
  const DrawerServerInfo({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    ref.watch(localeProvider);
    final serverInfo = ref.watch(serverInfoProvider);
    final user = ref.watch(currentUserProvider);
    final bool showVersionWarning = ref.watch(versionWarningPresentProvider(user));

    final appInfo = useState<Map<String, String?>>({});
    final fontSize = 12.0;
    final isDarkTheme = context.isDarkTheme;
    final latestVersion = serverInfo.latestVersion;
    final borderColor = context.colorScheme.outlineVariant;
    final textColor = context.textTheme.bodySmall?.color?.withValues(alpha: 0.87);

    useEffect(
      () {
        () async {
          final packageInfo = await PackageInfo.fromPlatform();
          appInfo.value = {
            "version": packageInfo.version,
            "buildNumber": packageInfo.buildNumber,
          };
        }();

        if (serverInfo.serverVersion.major == 0) {
          unawaited(ref.read(serverInfoProvider.notifier).getServerVersion());
        }

        return null;
      },
      [serverInfo.serverVersion.major],
    );

    TextStyle rowTextStyle() => TextStyle(fontSize: fontSize, color: textColor);

    return Container(
      decoration: BoxDecoration(
        color: context.colorScheme.surfaceContainerLowest,
        borderRadius: const BorderRadius.vertical(bottom: Radius.circular(8.0)),
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        children: [
          if (showVersionWarning) ...[
            const ServerUpdateNotification(),
            const SizedBox(height: 8),
          ],
          _InfoRow(
            label: "server_info_box_app_version".tr(),
            value: "${appInfo.value["version"] ?? '--'} build.${appInfo.value["buildNumber"] ?? '--'}",
            borderColor: borderColor,
            style: rowTextStyle(),
          ),
          _InfoRow(
            label: "server_version".tr(),
            value: serverInfo.serverVersion.major > 0
                ? "${serverInfo.serverVersion.major}.${serverInfo.serverVersion.minor}.${serverInfo.serverVersion.patch}"
                : "--",
            borderColor: borderColor,
            style: rowTextStyle(),
          ),
          _InfoRow(
            label: "server_info_box_server_url".tr(),
            value: getServerUrl() ?? '--',
            borderColor: borderColor,
            style: rowTextStyle(),
            tooltip: true,
            tooltipColor: context.primaryColor.withValues(alpha: 0.9),
            tooltipTextColor: isDarkTheme ? Colors.black : Colors.white,
          ),
          if (latestVersion != null)
            _InfoRow(
              labelWidget: Row(
                children: [
                  if (serverInfo.versionStatus == VersionStatus.serverOutOfDate)
                    const Padding(
                      padding: EdgeInsets.only(right: 5.0),
                      child: Icon(Icons.info, color: Color(0xFFF3BC6A), size: 12),
                    ),
                  Text("latest_version".tr(), style: rowTextStyle()),
                ],
              ),
              value: latestVersion.major > 0
                  ? "${latestVersion.major}.${latestVersion.minor}.${latestVersion.patch}"
                  : "--",
              borderColor: borderColor,
              style: rowTextStyle(),
            ),
        ],
      ),
    );
  }
}

class _InfoRow extends StatelessWidget {
  final String? label;
  final Widget? labelWidget;
  final String value;
  final Color borderColor;
  final TextStyle style;
  final bool tooltip;
  final Color? tooltipColor;
  final Color? tooltipTextColor;

  const _InfoRow({
    this.label,
    this.labelWidget,
    required this.value,
    required this.borderColor,
    required this.style,
    this.tooltip = false,
    this.tooltipColor,
    this.tooltipTextColor,
  }) : assert(
          label != null || labelWidget != null,
          'Either label or labelWidget must be provided',
        );

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 24.0,
      margin: const EdgeInsets.only(bottom: 4.0),
      decoration: BoxDecoration(
        border: Border(bottom: BorderSide(width: 1, color: borderColor)),
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Expanded(child: labelWidget ?? Text(label!, style: style)),
          const SizedBox(width: 8),
          tooltip
              ? Expanded(
                  child: Tooltip(
                    message: value,
                    verticalOffset: 0,
                    decoration: BoxDecoration(
                      color: tooltipColor,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    textStyle: TextStyle(color: tooltipTextColor),
                    preferBelow: false,
                    triggerMode: TooltipTriggerMode.tap,
                    child: Text(
                      value,
                      style: style.copyWith(overflow: TextOverflow.ellipsis),
                      textAlign: TextAlign.end,
                    ),
                  ),
                )
              : Expanded(flex: 0, child: Text(value, style: style)),
        ],
      ),
    );
  }
}
