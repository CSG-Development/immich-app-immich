import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/pages/login/curator_help.page.dart';

@RoutePage()
class UnableToDetectPage extends StatelessWidget {
  final VoidCallback? onRetry;

  const UnableToDetectPage({super.key, this.onRetry});

  @override
  Widget build(BuildContext context) {
    return CuratorHelpPage(
      titleKey: 'curator.unable_to_detect_screen_title',
      messageTitleKey: 'curator.unable_to_detect_screen_message_list_title',
      messageItemKeys: const [
        'curator.unable_to_detect_screen_message_list_1',
        'curator.unable_to_detect_screen_message_list_2',
        'curator.unable_to_detect_screen_message_list_3',
        'curator.unable_to_detect_screen_message_list_4',
        'curator.unable_to_detect_screen_message_list_5',
      ],
      footerKey: 'curator.unable_to_detect_screen_message_list_footer',
      onRetry: onRetry,
    );
  }
}
