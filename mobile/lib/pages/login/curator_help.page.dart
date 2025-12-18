import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

@RoutePage()
class CuratorHelpPage extends StatelessWidget {
  final String titleKey;
  final String messageTitleKey;
  final List<String> messageItemKeys;
  final String footerKey;
  final VoidCallback? onRetry;

  const CuratorHelpPage({
    super.key,
    required this.titleKey,
    required this.messageTitleKey,
    required this.messageItemKeys,
    required this.footerKey,
    this.onRetry,
  });

  Widget _footerLink(BuildContext context) {
    final raw = footerKey.tr();
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
                // TODO: implement help link open if needed
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
    final isPortraitMobile = context.isMobile && MediaQuery.of(context).orientation == Orientation.portrait;

    final content = Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          messageTitleKey.tr(),
          style: context.textTheme.bodyMedium,
        ),
        const SizedBox(height: 18),
        ...messageItemKeys.asMap().entries.map(
          (entry) => Padding(
            padding: const EdgeInsets.only(bottom: 12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('${entry.key + 1}. ', style: context.textTheme.bodyMedium),
                Expanded(child: Text(entry.value.tr(), style: context.textTheme.bodyMedium)),
              ],
            ),
          ),
        ),
        const SizedBox(height: 18),
        _footerLink(context),
      ],
    );

    return Scaffold(
      backgroundColor: context.colorScheme.surface,
      appBar: AppBar(
        backgroundColor: context.colorScheme.surface,
        title: Text(titleKey.tr()),
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
      body: LayoutBuilder(
        builder: (context, constraints) {
          return Padding(
            padding: const EdgeInsets.all(24.0),
            child: isPortraitMobile
                ? content
                : Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: content,
                    ),
                  ),
          );
        },
      ),
      bottomNavigationBar: onRetry != null
          ? BottomAppBar(
              color: context.colorScheme.surface,
              padding: const EdgeInsetsDirectional.symmetric(horizontal: 24, vertical: 12),
              child: Builder(
                builder: (context) {
                  final button = FilledButton.icon(
                    onPressed: onRetry,
                    icon: null,
                    label: Text('curator.button_action_retry'.tr()),
                  );

                  if (isPortraitMobile) {
                    return button;
                  }

                  return Center(
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(maxWidth: 400),
                      child: SizedBox(
                        width: double.infinity,
                        child: button,
                      ),
                    ),
                  );
                },
              ),
            )
          : null,
    );
  }
}

