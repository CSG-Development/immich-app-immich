import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:immich_mobile/platform/update_api.g.dart';
import 'package:logging/logging.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/infrastructure/app_update_progress.provider.dart';
import 'package:flutter/services.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/routing/router.dart';

Future<bool> showUpdateAvailableDialog({
  required BuildContext context,
  required String version,
  String? changelog,
  bool forced = false,
  required String downloadUrl,
  String? sha256,
}) async {
  final log = Logger('UpdateDialog');

  return await showDialog<bool>(
        context: context,
        barrierDismissible: !forced,
        builder: (ctx) => Consumer(
          builder: (ctx, ref, _) {
            final progressState = ref.watch(updateDownloadProvider);
            final int progress = progressState.percent;
            final bool isDownloading = progressState.isDownloading;
            return AlertDialog(
              title: const Text('curator.update_dialog_title').tr(),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('${'curator.update_dialog_version'.tr()} $version'),
                  if (changelog != null && changelog.isNotEmpty) ...[const SizedBox(height: 8), Text(changelog)],
                  if (isDownloading || (progress > 0 && progress < 100)) ...[
                    const SizedBox(height: 16),
                    LinearProgressIndicator(value: progress == 0 ? null : progress / 100.0),
                    const SizedBox(height: 8),
                    Text('${'curator.update_dialog_downloading'.tr()}... $progress%'),
                  ],
                ],
              ),
              actions: [
                if (!forced && !isDownloading)
                  TextButton(
                    onPressed: () {
                      // Clear dialog-specific callbacks in case they were set earlier
                      UpdateCallbacks.setUp(null);
                      ctx.maybePop(false);
                    },
                    child: const Text('curator.update_dialog_later').tr(),
                  ),
                if (progress >= 100) ...[
                  FilledButton(
                    onPressed: () async {
                      try {
                        final res = await UpdateApi().installDownloadedUpdate();
                        log.info('install_result success=${res.success} code=${res.errorCode} message=${res.message}');
                        if (!res.success) {
                          if (ctx.mounted) {
                            ImmichToast.show(
                              context: ctx,
                              msg:
                                  res.message ??
                                  '${'curator.update_dialog_installation_failed'.tr()} (${res.errorCode ?? 'unknown'})',
                              toastType: ToastType.error,
                              gravity: ToastGravity.BOTTOM,
                            );
                          }
                          // Clear dialog-specific callbacks to avoid leaks
                          UpdateCallbacks.setUp(null);
                          return; // Keep dialog open so user can retry
                        }
                      } catch (e) {
                        log.severe('install_error $e');
                        if (ctx.mounted) {
                          ImmichToast.show(
                            context: ctx,
                            msg: '${'curator.update_dialog_installation_error'.tr()} $e',
                            toastType: ToastType.error,
                            gravity: ToastGravity.BOTTOM,
                          );
                        }
                        // Clear dialog-specific callbacks to avoid leaks
                        UpdateCallbacks.setUp(null);
                        return;
                      }
                      // Clear dialog-specific callbacks when done
                      UpdateCallbacks.setUp(null);
                      if (ctx.mounted) ctx.maybePop(true);
                    },
                    child: const Text('curator.update_dialog_installation_update').tr(),
                  ),
                ] else if (isDownloading && progress < 100) ...[
                  TextButton(
                    onPressed: () {
                      // UI-level cancel: just clear callbacks and reset UI; download thread continues
                      UpdateCallbacks.setUp(null);
                      const MethodChannel('immich/update_control').invokeMethod('cancelDownload');
                      ref.read(updateDownloadProvider.notifier).reset();
                      if (ctx.mounted) {
                        ImmichToast.show(
                          context: ctx,
                          msg: 'curator.update_dialog_installation_canceled'.tr(),
                          toastType: ToastType.error,
                          gravity: ToastGravity.BOTTOM,
                        );
                      }
                    },
                    child: const Text('curator.update_dialog_installation_cancel').tr(),
                  ),
                  FilledButton(onPressed: null, child: const Text('curator.update_dialog_downloading').tr()),
                ] else ...[
                  FilledButton(
                    onPressed: () async {
                      log.info('download_clicked version=$version');
                      ref.read(updateDownloadProvider.notifier).start();
                      // Wire callbacks to update dialog state
                      UpdateCallbacks.setUp(
                        _DialogCallbacks(
                          onProgress: (p) {
                            log.info('download_progress percent=${p.percent}');
                            ref.read(updateDownloadProvider.notifier).setProgress(p.percent);
                          },
                          onError: (m) async {
                            log.warning('download_error message=$m');
                            ref.read(updateDownloadProvider.notifier).error(m);
                            // Clear dialog-specific callbacks
                            UpdateCallbacks.setUp(null);
                            // Close the update modal and show a toast using root navigator context
                            if (ctx.mounted) {
                              ctx.maybePop(false);
                            }
                            WidgetsBinding.instance.addPostFrameCallback((_) {
                              Future<void>.delayed(const Duration(milliseconds: 50), () {
                                final navState = ref.read(appRouterProvider).navigatorKey.currentState;
                                final overlayCtx = navState?.overlay?.context ?? navState?.context ?? ctx;
                                try {
                                  if (overlayCtx.mounted) {
                                    ImmichToast.show(
                                      context: overlayCtx,
                                      msg: m.isEmpty ? 'curator.update_dialog_download_error'.tr() : m,
                                      toastType: ToastType.error,
                                      gravity: ToastGravity.BOTTOM,
                                    );
                                    return;
                                  }
                                } catch (_) {}
                                if (ctx.mounted) {
                                  ImmichToast.show(
                                    context: ctx,
                                    msg: m.isEmpty ? 'curator.update_dialog_download_error'.tr() : m,
                                    toastType: ToastType.error,
                                    gravity: ToastGravity.BOTTOM,
                                  );
                                }
                              });
                            });
                          },
                          onCompleted: () {
                            log.info('download_completed');
                            ref.read(updateDownloadProvider.notifier).complete();
                            // Leave callbacks active until user presses Update
                          },
                        ),
                      );
                      try {
                        log.info('start_download version=$version url=$downloadUrl');
                        await UpdateApi().startDownload(version, downloadUrl, sha256);
                      } catch (_) {}
                    },
                    child: const Text('curator.update_dialog_download').tr(),
                  ),
                ],
              ],
            );
          },
        ),
      ) ??
      false;
}

class _DialogCallbacks extends UpdateCallbacks {
  _DialogCallbacks({required this.onProgress, required this.onError, required this.onCompleted});
  final void Function(DownloadProgress) onProgress;
  final void Function(String) onError;
  final VoidCallback onCompleted;

  @override
  void onDownloadCompleted() => onCompleted();

  @override
  void onDownloadError(String message) => onError(message);

  @override
  void onDownloadProgress(DownloadProgress progress) => onProgress(progress);
}
