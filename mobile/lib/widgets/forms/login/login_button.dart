import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

class LoginButton extends ConsumerWidget {
  final Function() onPressed;
  final bool withIcon;
  final bool isDisabled;

  const LoginButton({
    super.key,
    required this.onPressed,
    this.withIcon = true,
    this.isDisabled = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ElevatedButton.icon(
      style: ElevatedButton.styleFrom(
        padding: const EdgeInsets.symmetric(vertical: 12),
        backgroundColor: isDisabled ? Colors.grey[300] : null,
        foregroundColor: isDisabled ? Colors.grey[600] : null,
      ),
      onPressed: isDisabled ? null : onPressed,
      icon: withIcon ? const Icon(Icons.login_rounded) : null,
      label: Text(
        "login",
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: isDisabled ? Colors.grey[600] : null,
        ),
      ).tr(),
    );
  }
}
