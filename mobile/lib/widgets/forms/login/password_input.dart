import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/widgets/forms/login/input_decorations.dart';

class PasswordInput extends StatefulHookConsumerWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Function()? onSubmit;
  final bool hasExternalError;

  const PasswordInput({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onSubmit,
    this.hasExternalError = false,
  });

  @override
  ConsumerState<PasswordInput> createState() => _PasswordInputState();
}

class _PasswordInputState extends ConsumerState<PasswordInput> {
  String? _validateInput(String? email) {
    if (widget.hasExternalError) {
      return '';
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final isPasswordVisible = useState<bool>(false);

    return TextFormField(
      obscureText: !isPasswordVisible.value,
      controller: widget.controller,
      decoration: LoginInputDecorations.baseDecoration(
        context: context,
        labelText: 'password'.tr(),
        hintText: 'login_form_password_hint'.tr(),
        focusNode: widget.focusNode,
        suffixIcon: IconButton(
          onPressed: () => isPasswordVisible.value = !isPasswordVisible.value,
          icon: Icon(
            isPasswordVisible.value
                ? Icons.visibility_off_sharp
                : Icons.visibility_sharp,
          ),
        ),
      ).copyWith(
        errorStyle: widget.hasExternalError ? const TextStyle(height: 0) : null,
      ),
      validator: _validateInput,
      autovalidateMode: AutovalidateMode.always,
      autofillHints: const [AutofillHints.password],
      keyboardType: TextInputType.text,
      onFieldSubmitted: (_) => widget.onSubmit?.call(),
      focusNode: widget.focusNode,
      textInputAction: TextInputAction.go,
    );
  }
}
