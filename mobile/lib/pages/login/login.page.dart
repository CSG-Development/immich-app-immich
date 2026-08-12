import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hc_device/hc_device.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/developer_options.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/theme/theme_data.dart';
import 'package:immich_mobile/widgets/forms/login/curator_login_form.dart';
import 'package:immich_mobile/widgets/forms/login/remote_access_form.dart';

@RoutePage()
class LoginPage extends HookConsumerWidget {
  const LoginPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final authenticatedEmail = ref.read(deviceProvider).login ?? '';
    final devEnableSettingsOnLogin = ref.watch(developerOptionsProvider).devEnableSettingsOnLogin;

    final isRemoteAccessForm = useState<bool>(authenticatedEmail.isEmpty);
    final remoteAccessInitialEmailError = useState<String?>(null);

    return Scaffold(
      backgroundColor:
          Theme.of(context).extension<ImmichBrandColors>()?.chromeSurface ?? context.colorScheme.surface,
      appBar: isRemoteAccessForm.value
          ? null
          : AppBar(
              leading: isRemoteAccessForm.value
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.arrow_back),
                      onPressed: () {
                        isRemoteAccessForm.value = true;
                      },
                    ),
              backgroundColor: Colors.transparent,
              elevation: 0,
              systemOverlayStyle: context.isDarkTheme ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
              actions: devEnableSettingsOnLogin
                  ? [
                      IconButton(
                        icon: const Icon(Icons.settings, size: 24.0),
                        onPressed: () => context.pushRoute(const SettingsRoute()),
                      ),
                    ]
                  : null,
            ),
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () => FocusScope.of(context).unfocus(),
        child: LayoutBuilder(
          builder: (context, constraints) {
            final isWide = context.isTablet || context.orientation == Orientation.landscape;

            return SingleChildScrollView(
              child: Center(
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: isWide ? 400 : double.infinity,
                    minHeight: constraints.maxHeight,
                  ),
                  child: IntrinsicHeight(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(24.0, 24.0, 24.0, 24.0),
                      child: isRemoteAccessForm.value
                          ? RemoteAccessForm(
                              switchToCuratorLogin: () => isRemoteAccessForm.value = false,
                              initialEmailErrorMessage: remoteAccessInitialEmailError.value,
                              onInitialEmailErrorConsumed: () {
                                remoteAccessInitialEmailError.value = null;
                              },
                            )
                          : CuratorLoginForm(
                              switchToRemoteAccessForm: (initialEmailErrorMessage) {
                                remoteAccessInitialEmailError.value = initialEmailErrorMessage;
                                isRemoteAccessForm.value = true;
                              },
                            ),
                    ),
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }
}
