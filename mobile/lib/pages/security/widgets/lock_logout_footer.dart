import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

class LockLogoutFooter extends StatelessWidget {
  const LockLogoutFooter({
    super.key,
    required this.visible,
    required this.onLogout,
  });

  final bool visible;
  final VoidCallback onLogout;

  @override
  Widget build(BuildContext context) {
    if (!visible) return const SizedBox.shrink();

    return Align(
      alignment: Alignment.center,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8.0, horizontal: 24.0),
        child: GestureDetector(
          onTap: onLogout,
          child: Text(
            'log_out'.tr(),
            style: TextStyle(
              color: context.themeData.primaryColor,
              fontSize: 16,
              fontWeight: FontWeight.w500,
            ),
          ),
        ),
      ),
    );
  }
}

