import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/widgets/forms/login/login_brand_strings.dart';

class LoginBrandHeader extends StatelessWidget {
  const LoginBrandHeader({super.key, this.showLoginTitle = true});

  final bool showLoginTitle;

  @override
  Widget build(BuildContext context) {
    final scheme = context.colorScheme;
    final logoWidth = 128.0;

    return Column(
      children: [
        const SizedBox(height: 20),
        SvgPicture.asset(LoginBrandStrings.logoMarkSvg, width: logoWidth, fit: BoxFit.contain),
        if (showLoginTitle) ...[
          const SizedBox(height: 20),
          Text(
            'login'.tr(),
            textAlign: TextAlign.center,
            style: context.textTheme.titleLarge?.copyWith(
              fontSize: 34.0,
              fontWeight: FontWeight.w400,
              color: scheme.onSurface,
            ),
          ),
        ],
      ],
    );
  }
}
