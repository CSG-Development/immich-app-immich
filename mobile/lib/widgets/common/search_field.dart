import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/theme_extensions.dart';

class SearchField extends StatelessWidget {
  const SearchField({
    super.key,
    required this.hintText,
    this.autofocus = false,
    this.controller,
    this.focusNode,
    this.onChanged,
    this.onSubmitted,
    this.onTapOutside,
    this.contentPadding = const EdgeInsets.only(left: 24),
    this.prefixIcon,
    this.suffixIcon,
    this.filled = false,
    this.borderless = false,
  });

  final FocusNode? focusNode;
  final void Function(String)? onChanged;
  final void Function(String)? onSubmitted;
  final void Function(PointerDownEvent)? onTapOutside;
  final TextEditingController? controller;
  final String hintText;
  final EdgeInsetsGeometry contentPadding;
  final Widget? prefixIcon;
  final Widget? suffixIcon;
  final bool autofocus;
  final bool filled;
  final bool borderless;

  @override
  Widget build(BuildContext context) {
    const borderRadius = BorderRadius.all(Radius.circular(25));
    OutlineInputBorder borderFor(Color color) => OutlineInputBorder(
      borderRadius: borderRadius,
      borderSide: borderless ? BorderSide.none : BorderSide(color: color),
    );

    return TextField(
      controller: controller,
      autofocus: autofocus,
      focusNode: focusNode,
      onChanged: onChanged,
      onTapOutside: onTapOutside ?? (_) => focusNode?.unfocus(),
      onSubmitted: onSubmitted,
      decoration: InputDecoration(
        contentPadding: contentPadding,
        filled: filled,
        fillColor: context.primaryColor.withValues(alpha: 0.1),
        hintStyle: context.textTheme.bodyLarge?.copyWith(color: context.themeData.colorScheme.onSurfaceSecondary),
        border: borderFor(context.colorScheme.surfaceDim),
        enabledBorder: borderFor(context.colorScheme.surfaceContainer),
        disabledBorder: borderFor(context.colorScheme.surfaceDim),
        focusedBorder: borderFor(
          borderless ? Colors.transparent : context.colorScheme.primary.withAlpha(100),
        ),
        prefixIcon: prefixIcon,
        suffixIcon: suffixIcon,
        hintText: hintText,
      ),
    );
  }
}
