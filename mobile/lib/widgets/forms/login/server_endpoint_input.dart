import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:immich_mobile/widgets/forms/login/input_decorations.dart';

class ServerEndpointInput extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Function()? onSubmit;
  final EdgeInsets padding;

  const ServerEndpointInput({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onSubmit,
    this.padding = const EdgeInsets.only(top: 16.0),
  });

  @override
  State<ServerEndpointInput> createState() => _ServerEndpointInputState();
}

class _ServerEndpointInputState extends State<ServerEndpointInput> {
  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_handleTextChange);
  }

  @override
  void dispose() {
    widget.controller.removeListener(_handleTextChange);
    super.dispose();
  }

  void _handleTextChange() {
    setState(() {});
  }

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
    return Padding(
      padding: widget.padding,
      child: TextFormField(
        controller: widget.controller,
        decoration: LoginInputDecorations.baseDecoration(
          context: context,
          labelText: 'login_form_endpoint_url'.tr(),
          hintText: 'login_form_endpoint_hint'.tr(),
          focusNode: widget.focusNode,
          suffixIcon: widget.controller.text.isEmpty
              ? null
              : IconButton(
                  onPressed: () {
                    widget.controller.clear();
                    setState(() {});
                  },
                  icon: const Icon(Icons.highlight_off),
                ),
          errorMaxLines: 4,
        ),
        validator: _validateInput,
        autovalidateMode: AutovalidateMode.always,
        focusNode: widget.focusNode,
        autofillHints: const [AutofillHints.url],
        keyboardType: TextInputType.url,
        autocorrect: false,
        onFieldSubmitted: (_) => widget.onSubmit?.call(),
        textInputAction: TextInputAction.go,
      ),
    );
  }
}
