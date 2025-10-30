import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/infrastructure/app_update_progress.provider.dart';
import 'package:immich_mobile/platform/update_api.g.dart';
import 'package:flutter/services.dart';

class UpdateDownloadBanner extends ConsumerWidget {
  const UpdateDownloadBanner({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final state = ref.watch(updateDownloadProvider);
    if (!state.isDownloading) return const SizedBox.shrink();

    return Material(
      color: Theme.of(context).colorScheme.surfaceContainerHigh,
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 12.0),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Downloading update…'),
                    const SizedBox(height: 6),
                    LinearProgressIndicator(value: state.percent == 0 ? null : state.percent / 100.0),
                  ],
                ),
              ),
              const SizedBox(width: 12),
              TextButton(
                onPressed: () async {
                  UpdateCallbacks.setUp(null);
                  await const MethodChannel('immich/update_control').invokeMethod('cancelDownload');
                  ref.read(updateDownloadProvider.notifier).reset();
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Canceled')),
                    );
                  }
                },
                child: const Text('Cancel'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}


