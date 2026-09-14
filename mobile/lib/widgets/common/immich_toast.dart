import 'package:flutter/material.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:immich_mobile/widgets/common/immich_toast_style.dart';

export 'package:immich_mobile/widgets/common/immich_toast_style.dart' show ToastType;
export 'package:immich_mobile/widgets/common/immich_toast_undo.dart';

class ImmichToast {
  static void dismiss() {
    final fToast = FToast();
    fToast.removeCustomToast();
    fToast.removeQueuedCustomToasts();
  }

  static show({
    required BuildContext context,
    required String msg,
    ToastType toastType = ToastType.info,
    ToastGravity gravity = ToastGravity.BOTTOM,
    int durationInSecond = 3,
  }) {
    final fToast = FToast()..init(context);

    fToast.showToast(
      child: ImmichToastStyle.pill(context: context, msg: msg, toastType: toastType),
      positionedToastBuilder: (context, child, gravity) => ImmichToastStyle.positioned(
        context: context,
        child: child,
        gravity: gravity,
        ignorePointer: true,
      ),
      gravity: gravity,
      toastDuration: Duration(seconds: durationInSecond),
    );
  }
}
