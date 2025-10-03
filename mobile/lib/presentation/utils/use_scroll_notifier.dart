import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/presentation/utils/scroll_notifier_utils.dart';

ScrollController useScrollNotifier(WidgetRef ref) {
  final controller = useScrollController();

  useEffect(() {
    final detach = attachScrollNotifierToController(controller: controller, ref: ref);
    return detach;
  }, [controller]);

  return controller;
}



