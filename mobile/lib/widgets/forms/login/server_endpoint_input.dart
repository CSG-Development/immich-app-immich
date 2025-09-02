import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/widgets/forms/login/input_decorations.dart';
import 'package:immich_mobile/widgets/forms/login/trim_formatter.dart';

class ServerEndpointInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onSubmit;
  final bool hasExternalError;

  const ServerEndpointInput({
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
            labelText: 'curator.login_form_endpoint_url'.tr(),
            hintText: 'curator.login_form_endpoint_hint'.tr(),
            isError: hasExternalError,
            suffixIcon: shouldShowClearButton
                ? IconButton(
                    onPressed: controller.clear,
                    icon: const Icon(Icons.highlight_off),
                  )
                : null,
          ),
          autovalidateMode: AutovalidateMode.always,
          focusNode: focusNode,
          autofillHints: const [AutofillHints.url],
          keyboardType: TextInputType.url,
          autocorrect: false,
          onFieldSubmitted: (_) => onSubmit?.call(),
          textInputAction: TextInputAction.go,
        );
      },
    );
  }
}
