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
  final Widget? suffixIcon;
  final String? label;
  final String? hintText;
  final bool isDetecting;
  final bool isEmpty;

  const ServerEndpointInput({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onSubmit,
    this.hasExternalError = false,
    this.leadingIcon,
    this.suffixIcon,
    this.label,
    this.hintText,
    this.isDetecting = false,
    this.isEmpty = true,
  });

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge([controller, focusNode]),
      builder: (context, _) {
        final bool shouldShowClearButton = controller.text.isNotEmpty && focusNode.hasFocus;
        return TextFormField(
          controller: controller,
          inputFormatters: const [TrimFormatter()],
          decoration: LoginInputDecorations.baseDecoration(
            context: context,
            labelText: label ?? 'curator.login_form_endpoint_url'.tr(),
            hintText:
                hintText ??
                (isDetecting
                    ? 'curator.oobe_welcome_dropdown_detecting'.tr()
                    : isEmpty
                    ? 'curator.login_form_endpoint_hint'.tr()
                    : ''),
            isError: hasExternalError,
            suffixIcon: shouldShowClearButton
                ? IconButton(onPressed: controller.clear, icon: const Icon(Icons.highlight_off))
                : suffixIcon,
            prefixIcon: leadingIcon,
            floatingLabelBehavior: isDetecting ? FloatingLabelBehavior.always : FloatingLabelBehavior.auto,
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
