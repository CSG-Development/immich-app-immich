import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

@RoutePage()
class UnableToDetectPage extends StatelessWidget {
  final VoidCallback? onRetry;

  const UnableToDetectPage({super.key, this.onRetry});

  Widget footerLink(BuildContext context) {
    final raw = 'curator.unable_to_detect_screen_message_list_footer'.tr();
    final spans = <TextSpan>[];

    raw.splitMapJoin(
      RegExp(r'<link>(.*?)</link>'),
      onMatch: (m) {
        spans.add(
          TextSpan(
            text: m.group(1),
            style: context.textTheme.bodyMedium?.copyWith(
              color: context.colorScheme.primary,
              decoration: TextDecoration.underline,
              decorationColor: context.colorScheme.primary,
            ),
            recognizer: TapGestureRecognizer()
              ..onTap = () {
                debugPrint('onTap');
                // launchUrl(
                //     Uri.parse('https://your-help-url.example'),
                //     mode: LaunchMode.externalApplication,
                //   );
              },
          ),
        );
        return '';
      },
      onNonMatch: (text) {
        if (text.isNotEmpty) {
          spans.add(TextSpan(text: text, style: context.textTheme.bodyMedium));
        }
        return '';
      },
    );

    return RichText(text: TextSpan(children: spans));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: context.colorScheme.surface,
        title: Text('curator.unable_to_detect_screen_title'.tr()),
        titleTextStyle: context.textTheme.titleLarge?.copyWith(
          fontWeight: FontWeight.w600,
          fontSize: 18,
        ),
        centerTitle: true,
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pop();
          },
        ),
      ),
      body: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('curator.unable_to_detect_screen_message_list_title'.tr(), style: context.textTheme.bodyMedium),
            const SizedBox(height: 18),
            ...[
              'curator.unable_to_detect_screen_message_list_1'.tr(),
              'curator.unable_to_detect_screen_message_list_2'.tr(),
              'curator.unable_to_detect_screen_message_list_3'.tr(),
              'curator.unable_to_detect_screen_message_list_4'.tr(),
              'curator.unable_to_detect_screen_message_list_5'.tr(),
            ].asMap().entries.map(
              (entry) => Padding(
                padding: const EdgeInsets.only(bottom: 12.0),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('${entry.key + 1}. ', style: context.textTheme.bodyMedium),
                    Expanded(child: Text(entry.value, style: context.textTheme.bodyMedium)),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 18),
            footerLink(context),
            // Text('curator.unable_to_detect_screen_message_list_footer'.tr(), style: context.textTheme.bodyMedium),
          ],
        ),
      ),
      bottomNavigationBar: onRetry != null
          ? BottomAppBar(
              color: context.colorScheme.surface,
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 24, vertical: 12),
              child: FilledButton.icon(onPressed: onRetry, icon: null, label: Text('curator.button_action_retry'.tr())),
            )
          : null,
    );
  }
}
