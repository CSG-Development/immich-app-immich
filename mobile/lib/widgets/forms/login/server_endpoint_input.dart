import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:immich_mobile/widgets/forms/login/input_decorations.dart';
import 'package:immich_mobile/widgets/forms/login/trim_formatter.dart';

class ServerEndpointInput extends StatelessWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback? onSubmit;

  const ServerEndpointInput({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onSubmit,
  });

  String? _validateInput(String? url) {
    if (url == null || url.isEmpty) return null;

    final parsedUrl = Uri.tryParse(sanitizeUrl(url));
    if (parsedUrl == null ||
        !parsedUrl.isAbsolute ||
        !parsedUrl.scheme.startsWith("http") ||
        parsedUrl.host.isEmpty) {
      return 'login_form_err_invalid_url'.tr();
    }

    return null;
  }

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
            suffixIcon: shouldShowClearButton
                ? IconButton(
                    onPressed: controller.clear,
                    icon: const Icon(Icons.highlight_off),
                  )
                : null,
          ),
          validator: _validateInput,
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
