import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/utils/input_decorations.dart';
import 'package:immich_mobile/utils/trim_formatter.dart';

class ServerEndpointInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onSubmit;
  final bool hasExternalError;
  final Widget? leadingIcon;
  final String? label;

  const ServerEndpointInput({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onSubmit,
    this.hasExternalError = false,
    this.leadingIcon,
    this.label
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
            labelText: label ?? 'curator.login_form_endpoint_url'.tr(),
            hintText: 'curator.login_form_endpoint_hint'.tr(),
            isError: hasExternalError,
            suffixIcon: shouldShowClearButton
                ? IconButton(
                    onPressed: controller.clear,
                    icon: const Icon(Icons.highlight_off),
                  )
                : null,
            prefixIcon: leadingIcon,
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
