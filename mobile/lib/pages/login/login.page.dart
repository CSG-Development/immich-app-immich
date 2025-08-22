import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/widgets/forms/login/curator_login_form.dart';
import 'package:package_info_plus/package_info_plus.dart';

@RoutePage()
class LoginPage extends HookConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appVersion = useState('0.0.0');

    getAppInfo() async {
      PackageInfo packageInfo = await PackageInfo.fromPlatform();
      appVersion.value = packageInfo.version;
    }

    useEffect(
      () {
        getAppInfo();
        return null;
      },
    );

    return Scaffold(
      body: Stack(
        children: [
          CuratorLoginForm(),
          Positioned(
            top: 0,
            left: 0,
            right: 0,
            child: AppBar(
              backgroundColor: Colors.transparent,
              elevation: 0,
              systemOverlayStyle: context.isDarkTheme
                  ? SystemUiOverlayStyle.light
                  : SystemUiOverlayStyle.dark,
              actions: [
                IconButton(
                  icon: Icon(
                    Icons.settings,
                    size: 24.0,
                    color: context.isDarkTheme
                        ? const Color(0xDEFFFFFF)
                        : const Color(0xDE000000),
                  ),
                  onPressed: () => context.pushRoute(const SettingsRoute()),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
