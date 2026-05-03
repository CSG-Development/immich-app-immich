import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/utils/url_helper.dart';
import 'package:immich_mobile/widgets/settings/networking_settings/external_network_preference.dart';
import 'package:immich_mobile/widgets/settings/networking_settings/local_network_preference.dart';

class NetworkingSettings extends HookConsumerWidget {
  const NetworkingSettings({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final currentEndpoint = getServerUrl();

    return ListView(
      padding: const EdgeInsets.only(bottom: 96),
      physics: const ClampingScrollPhysics(),
      children: <Widget>[
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 16, bottom: 8),
          child: NetworkPreferenceTitle(
            title: "current_server_address".tr().toUpperCase(),
            icon: (currentEndpoint?.startsWith('https') ?? false) ? Icons.https_outlined : Icons.http_outlined,
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 8),
          child: Card(
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: const BorderRadius.all(Radius.circular(16)),
              side: BorderSide(color: context.colorScheme.surfaceContainerHighest, width: 1),
            ),
            child: ListTile(
              leading: currentEndpoint != null
                  ? const Icon(Icons.check_circle_rounded, color: Colors.green)
                  : const Icon(Icons.circle_outlined),
              title: Text(
                currentEndpoint ?? "--",
                style: TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: context.primaryColor,
                ),
              ),
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 10.0),
          child: Divider(color: context.colorScheme.surfaceContainerHighest),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 8, left: 16, bottom: 16),
          child: NetworkPreferenceTitle(title: "local_network".tr().toUpperCase(), icon: Icons.home_outlined),
        ),
        const LocalNetworkPreference(enabled: true),
        Padding(
          padding: const EdgeInsets.only(top: 32, left: 16, bottom: 16),
          child: NetworkPreferenceTitle(title: "external_network".tr().toUpperCase(), icon: Icons.dns_outlined),
        ),
        const ExternalNetworkPreference(enabled: true),
      ],
    );
  }
}

class NetworkPreferenceTitle extends StatelessWidget {
  const NetworkPreferenceTitle({super.key, required this.icon, required this.title});

  final IconData icon;
  final String title;

  @override
  Widget build(BuildContext context) {
    return Row(
      children: [
        Icon(icon, color: context.colorScheme.onSurface.withAlpha(150)),
        const SizedBox(width: 8),
        Text(
          title,
          style: context.textTheme.displaySmall?.copyWith(
            color: context.colorScheme.onSurface.withAlpha(200),
            fontWeight: FontWeight.w500,
          ),
        ),
      ],
    );
  }
}
