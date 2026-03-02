import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.state.dart';

class AssetCountSliver extends ConsumerWidget {
  const AssetCountSliver({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final assetCountAsync = ref.watch(timelineTotalAssetsProvider);
    final assetCount = assetCountAsync.value ?? 0;

    return SliverToBoxAdapter(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            const Icon(Icons.photo_library_outlined, size: 20),
            const SizedBox(width: 8),
            Text(
              'items_count'.t(
                context: context,
                args: {
                  'count': assetCount,
                },
              ),
              style: context.textTheme.bodyLarge,
            ),
          ],
        ),
      ),
    );
  }
}


