import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/widgets/forms/login/input_decorations.dart';

class EmailInput extends StatefulWidget {
  final TextEditingController controller;
  final FocusNode focusNode;
  final Function()? onSubmit;
  final bool hasExternalError;

  const EmailInput({
    super.key,
    required this.controller,
    required this.focusNode,
    this.onSubmit,
    this.hasExternalError = false,
  });

  @override
  State<EmailInput> createState() => _EmailInputState();
}

class _EmailInputState extends State<EmailInput> {
  String? _validateInput(String? email) {
    if (widget.hasExternalError) {
      return '';
    }

    if (email == null || email == '') return null;
    if (email.length < 5) return null;
    if (email.endsWith(' ')) return 'login_form_err_trailing_whitespace'.tr();
    if (email.startsWith(' ')) return 'login_form_err_leading_whitespace'.tr();
    if (email.contains(' ') || !email.contains('@')) {
      return 'login_form_err_invalid_email'.tr();
    }
    return null;
  }

  @override
  Widget build(BuildContext context) {
    return TextFormField(
      autofocus: true,
      controller: widget.controller,
      decoration: LoginInputDecorations.baseDecoration(
        context: context,
        labelText: 'email'.tr(),
        hintText: 'login_form_email_hint'.tr(),
        focusNode: widget.focusNode,
      ).copyWith(
        errorStyle: widget.hasExternalError 
            ? const TextStyle(height: 0)
            : null,
      ),
      validator: _validateInput,
      autovalidateMode: AutovalidateMode.always,
      autofillHints: const [AutofillHints.email],
      keyboardType: TextInputType.emailAddress,
      onFieldSubmitted: (_) => widget.onSubmit?.call(),
      focusNode: widget.focusNode,
      textInputAction: TextInputAction.next,
    );
  }
}
