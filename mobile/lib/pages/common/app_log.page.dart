import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/log.model.dart';
import 'package:immich_mobile/domain/services/log.service.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/immich_logger.service.dart';

@RoutePage()
class AppLogPage extends HookConsumerWidget {
  const AppLogPage({super.key});

  static const _allSessionsKey = '';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final immichLogger = LogService.I;
    final shouldReload = useState(false);
    final selectedSessionId = useState<String?>(null);

    final sessions = useFuture(useMemoized(() => immichLogger.getSessions(), [shouldReload.value]));
    final logMessages = useFuture(
      useMemoized(
        () => immichLogger.getMessages(sessionId: selectedSessionId.value),
        [shouldReload.value, selectedSessionId.value],
      ),
    );

    // Drop stale filter if the session was cleared / pruned away.
    useEffect(() {
      final sessionId = selectedSessionId.value;
      final data = sessions.data;
      if (sessionId == null || data == null) {
        return null;
      }
      if (!data.any((s) => s.sessionId == sessionId)) {
        selectedSessionId.value = null;
      }
      return null;
    }, [sessions.data]);

    Widget colorStatusIndicator(Color color) {
      return Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 10,
            height: 10,
            decoration: BoxDecoration(color: color, shape: BoxShape.circle),
          ),
        ],
      );
    }

    Widget buildLeadingIcon(LogLevel level) => switch (level) {
      LogLevel.info => colorStatusIndicator(context.primaryColor),
      LogLevel.severe => colorStatusIndicator(Colors.redAccent),
      LogLevel.warning => colorStatusIndicator(Colors.orangeAccent),
      _ => colorStatusIndicator(Colors.grey),
    };

    Color getTileColor(LogLevel level) => switch (level) {
      LogLevel.info => Colors.transparent,
      LogLevel.severe => Colors.redAccent.withValues(alpha: 0.25),
      LogLevel.warning => Colors.orangeAccent.withValues(alpha: 0.25),
      _ => context.primaryColor.withValues(alpha: 0.1),
    };

    String formatSessionLabel(LogSessionInfo session) {
      final shortId = session.sessionId.length > 8 ? session.sessionId.substring(0, 8) : session.sessionId;
      final when = DateFormat('MMM d HH:mm').format(session.startedAt.toLocal());
      final current = session.sessionId == immichLogger.sessionId ? ' · ${'logs_current_session'.tr()}' : '';
      return '${session.runtime.name} · $when · $shortId · ${session.rowCount}$current';
    }

    return Scaffold(
      appBar: AppBar(
        title: Text('logs'.tr(), style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16.0)),
        scrolledUnderElevation: 1,
        elevation: 2,
        actions: [
          IconButton(
            icon: Icon(
              Icons.delete_outline_rounded,
              color: context.primaryColor,
              semanticLabel: "clear_logs".tr(),
              size: 20.0,
            ),
            onPressed: () async {
              await immichLogger.clearLogs();
              selectedSessionId.value = null;
              shouldReload.value = !shouldReload.value;
            },
          ),
          Builder(
            builder: (BuildContext iconContext) {
              return IconButton(
                icon: Icon(
                  Icons.share_rounded,
                  color: context.primaryColor,
                  semanticLabel: "share_logs".tr(),
                  size: 20.0,
                ),
                onPressed: () {
                  // Share exactly what is shown for the current filter.
                  ImmichLogger.shareLogs(
                    iconContext,
                    sessionId: selectedSessionId.value,
                    messages: logMessages.data,
                  );
                },
              );
            },
          ),
        ],
        leading: IconButton(
          onPressed: () {
            context.maybePop();
          },
          icon: const Icon(Icons.arrow_back_ios_new_rounded, size: 20.0),
        ),
        centerTitle: true,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: DropdownMenu<String>(
              key: ValueKey('session-filter-${shouldReload.value}-${sessions.data?.length ?? 0}'),
              initialSelection: selectedSessionId.value ?? _allSessionsKey,
              expandedInsets: EdgeInsets.zero,
              label: Text('logs_session_filter'.tr()),
              dropdownMenuEntries: [
                DropdownMenuEntry(value: _allSessionsKey, label: 'logs_all_sessions'.tr()),
                for (final session in sessions.data ?? const <LogSessionInfo>[])
                  DropdownMenuEntry(value: session.sessionId, label: formatSessionLabel(session)),
              ],
              onSelected: (value) {
                selectedSessionId.value = (value == null || value == _allSessionsKey) ? null : value;
              },
              menuStyle: const MenuStyle(
                shape: WidgetStatePropertyAll(
                  RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(15))),
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView.separated(
              separatorBuilder: (context, index) {
                return const Divider(height: 0);
              },
              itemCount: logMessages.data?.length ?? 0,
              itemBuilder: (context, index) {
                var logMessage = logMessages.data![index];
                return ListTile(
                  onTap: () => context.pushRoute(AppLogDetailRoute(logMessage: logMessage)),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded),
                  visualDensity: VisualDensity.compact,
                  dense: true,
                  tileColor: getTileColor(logMessage.level),
                  minLeadingWidth: 10,
                  title: Text(
                    truncateLogMessage(logMessage.message, 4),
                    style: TextStyle(fontSize: 14.0, color: context.colorScheme.onSurface),
                  ),
                  subtitle: Text(
                    "at ${DateFormat("HH:mm:ss.SSS").format(logMessage.createdAt)} in ${logMessage.logger}"
                    " · ${logMessage.runtime.name}",
                    style: TextStyle(fontSize: 12.0, color: context.colorScheme.onSurfaceSecondary),
                  ),
                  leading: buildLeadingIcon(logMessage.level),
                );
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Truncate the log message to a certain number of lines
  /// @param int maxLines - Max number of lines to truncate
  String truncateLogMessage(String message, int maxLines) {
    List<String> messageLines = message.split("\n");
    if (messageLines.length < maxLines) {
      return message;
    }
    return "${messageLines.sublist(0, maxLines).join("\n")} ...";
  }
}
