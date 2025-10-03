import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/providers/asset_viewer/scroll_notifier.provider.dart';

typedef RemoveScrollListener = void Function();

RemoveScrollListener attachScrollNotifierToController({
  required ScrollController controller,
  required WidgetRef ref,
}) {
  void onScroll() {
    if (!controller.hasClients) return;
    final position = controller.position;
    ref.read(scrollNotifierProvider).handleOffset(
          offset: controller.offset,
          minScrollExtent: position.minScrollExtent,
          maxScrollExtent: position.maxScrollExtent,
        );
  }

  controller.addListener(onScroll);
  return () => controller.removeListener(onScroll);
}



