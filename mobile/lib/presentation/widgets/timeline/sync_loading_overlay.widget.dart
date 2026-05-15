import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/sync_status.provider.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.state.dart';
import 'package:immich_mobile/widgets/common/immich_loading_indicator.dart';

class SyncLoadingOverlay extends HookConsumerWidget {
  final double topOffset;

  const SyncLoadingOverlay({super.key, this.topOffset = 0.0});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final syncStatus = ref.watch(syncStatusProvider);
    final totalAssetsAsync = ref.watch(timelineTotalAssetsProvider);
    final hasAssets = (totalAssetsAsync.valueOrNull ?? 0) > 0;

    final localSyncing = syncStatus.localSyncStatus == SyncStatus.syncing;
    final remoteSyncing = syncStatus.remoteSyncStatus == SyncStatus.syncing;
    final anySyncing = localSyncing || remoteSyncing;

    if (hasAssets) {
      return const SizedBox.shrink();
    }

    final showLoading = useState(true);
    final syncWasActive = useState(false);

    useEffect(() {
      if (anySyncing && !syncWasActive.value) {
        syncWasActive.value = true;
      }
      return null;
    }, [anySyncing]);

    final timeoutTimerRef = useRef<Timer?>(null);
    useEffect(() {
      timeoutTimerRef.value = Timer(const Duration(seconds: 30), () {
        if (showLoading.value) {
          showLoading.value = false;
        }
      });
      return () {
        timeoutTimerRef.value?.cancel();
        timeoutTimerRef.value = null;
      };
    }, const []);

    useEffect(() {
      if (hasAssets && showLoading.value) {
        showLoading.value = false;
        timeoutTimerRef.value?.cancel();
      }
      return null;
    }, [hasAssets]);

    final debounceTimerRef = useRef<Timer?>(null);
    useEffect(() {
      debounceTimerRef.value?.cancel();

      if (!showLoading.value) {
        return null;
      }

      if (!syncWasActive.value) {
        return null;
      }

      final localDone = syncStatus.localSyncStatus != SyncStatus.syncing;
      final remoteDone = syncStatus.remoteSyncStatus != SyncStatus.syncing;
      final bothDone = localDone && remoteDone;

      if (bothDone) {
        debounceTimerRef.value = Timer(const Duration(milliseconds: 500), () {
          if (showLoading.value) {
            showLoading.value = false;
            timeoutTimerRef.value?.cancel();
          }
        });
      }

      return () {
        debounceTimerRef.value?.cancel();
      };
    }, [syncStatus, syncWasActive.value]);

    if (!showLoading.value) {
      return const SizedBox.shrink();
    }

    return Positioned(
      top: topOffset,
      left: 0,
      right: 0,
      bottom: 0,
      child: const IgnorePointer(child: Center(child: ImmichLoadingIndicator())),
    );
  }
}
