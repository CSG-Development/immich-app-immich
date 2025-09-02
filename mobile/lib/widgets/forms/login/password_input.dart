import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/widgets/forms/login/input_decorations.dart';
import 'package:immich_mobile/widgets/forms/login/trim_formatter.dart';

class PasswordInput extends HookConsumerWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onSubmit;
  final bool hasExternalError;

  const PasswordInput({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onSubmit,
    this.hasExternalError = false,
  });

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isPasswordVisible = useState<bool>(false);

    return TextFormField(
      obscureText: !isPasswordVisible.value,
      controller: controller,
      inputFormatters: const [TrimFormatter()],
      decoration: LoginInputDecorations.baseDecoration(
        context: context,
        labelText: 'password'.tr(),
        hintText: 'curator.login_form_password_hint'.tr(),
        suffixIcon: IconButton(
          style: IconButton.styleFrom(
            foregroundColor: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          onPressed: () => isPasswordVisible.value = !isPasswordVisible.value,
          icon: Icon(
            isPasswordVisible.value
                ? Icons.visibility_off_sharp
                : Icons.visibility_sharp,
          ),
        ),
        isError: hasExternalError,
      ),
      autovalidateMode: AutovalidateMode.always,
      autofillHints: const [AutofillHints.password],
      keyboardType: TextInputType.text,
      onFieldSubmitted: (_) => onSubmit?.call(),
      focusNode: focusNode,
      textInputAction: TextInputAction.go,
    );
  }
}
