import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/theme/theme_data.dart';
import 'package:immich_mobile/widgets/forms/change_password_form.dart';

@RoutePage()
class ChangePasswordPage extends HookConsumerWidget {
  const ChangePasswordPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      backgroundColor:
          Theme.of(context).extension<ImmichBrandColors>()?.chromeSurface ?? Theme.of(context).colorScheme.surface,
      body: const ChangePasswordForm(),
    );
  }
}
