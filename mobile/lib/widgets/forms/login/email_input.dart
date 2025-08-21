import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/widgets/forms/login/input_decorations.dart';
import 'package:immich_mobile/widgets/forms/login/trim_formatter.dart';

class EmailInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onSubmit;
  final bool hasExternalError;

  const EmailInput({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onSubmit,
    this.hasExternalError = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        final bool shouldShowClearButton =
            controller.text.isNotEmpty && focusNode.hasFocus;

        return TextFormField(
          controller: controller,
          inputFormatters: const [TrimFormatter()],
          decoration: LoginInputDecorations.baseDecoration(
            context: context,
            labelText: 'email'.tr(),
            hintText: 'curator.login_form_email_hint'.tr(),
            suffixIcon: shouldShowClearButton
                ? IconButton(
                    onPressed: controller.clear,
                    icon: const Icon(Icons.highlight_off),
                  )
                : null,
            isError: hasExternalError,
          ),
          autovalidateMode: AutovalidateMode.always,
          autofillHints: const [AutofillHints.email],
          keyboardType: TextInputType.emailAddress,
          onFieldSubmitted: (_) => onSubmit?.call(),
          focusNode: focusNode,
          textInputAction: TextInputAction.next,
        );
      },
    );
  }
}
