import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/developer_options.provider.dart';
import 'package:immich_mobile/widgets/forms/login/server_endpoint_input.dart';

class DeveloperOptionsModal extends HookConsumerWidget {
  final Future<void> Function()? onSuccess;

  const DeveloperOptionsModal({super.key, this.onSuccess});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final serverEndpointInputController = useTextEditingController();
    final serverEndpointInputFocusNode = useFocusNode();
    final devEnableSettingsOnLogin = ref.watch(developerOptionsProvider).devEnableSettingsOnLogin;

    useEffect(() {
      final devStaticDeviceUrl = ref.read(developerOptionsProvider).devStaticDeviceUrl;
      if (devStaticDeviceUrl != null) {
        serverEndpointInputController.text = devStaticDeviceUrl;
      }
      return null;
    }, []);

    handleSubmit(String value) {
      ref.read(developerOptionsProvider.notifier).updateDevStaticDeviceUrl(serverEndpointInputController.value.text);
    }

    final actions = [
      () {
        return TextButton(
          onPressed: () => Navigator.of(context).pop(),
          style: TextButton.styleFrom(
            minimumSize: Size.zero,
            padding: const EdgeInsets.all(12.0),
            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          ),
          child: Text('cancel'.tr()),
        );
      },
      () {
        return ValueListenableBuilder(
          valueListenable: serverEndpointInputController,
          builder: (_, value, _) {
            final uri = Uri.tryParse(value.text);
            final isValidUrl = uri != null && uri.hasScheme && uri.hasAuthority;
            return TextButton(
              onPressed: () {
                if (!isValidUrl) return;
                handleSubmit(value.text);
                Navigator.of(context).pop();
              },
              style: TextButton.styleFrom(
                minimumSize: Size.zero,
                padding: const EdgeInsets.all(12.0),
                tapTargetSize: MaterialTapTargetSize.shrinkWrap,
              ),
              child: Text(
                'ok'.tr(),
                style: TextStyle(color: !isValidUrl ? const Color(0xFF9E9E9E) : context.colorScheme.primary),
              ),
            );
          },
        );
      },
    ];

    final isWide = context.isTablet || context.orientation == Orientation.landscape;

    Widget? buildIconDevice() {
      final icon = Image.asset("assets/device.webp", width: 50, height: 40);
      return Padding(
        padding: const EdgeInsets.only(left: 8.0),
        child: SizedBox(height: 40.0, width: 50.0, child: icon),
      );
    }

    return AlertDialog(
      title: Text('curator.developer_options.developer_options_title'.tr()),
      content: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: isWide ? 400 : double.infinity),
        child: SizedBox(
          width: double.maxFinite,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              const SizedBox(height: 12),
              ServerEndpointInput(
                label: 'curator.developer_options.static_device'.tr(),
                hintText: 'curator.developer_options.static_device'.tr(),
                controller: serverEndpointInputController,
                focusNode: serverEndpointInputFocusNode,
                leadingIcon: buildIconDevice(),
                isDetecting: false,
                isEmpty: serverEndpointInputController.text.isEmpty,
                onSubmit: () => handleSubmit(serverEndpointInputController.text),
              ),
              const SizedBox(height: 12.0),
              SwitchListTile.adaptive(
                contentPadding: const EdgeInsets.all(0),
                value: devEnableSettingsOnLogin,
                onChanged: (value) => ref.read(developerOptionsProvider.notifier).updateDevEnableSettingsOnLogin(value),
                activeThumbColor: context.primaryColor,
                dense: true,
                title: Text('curator.developer_options.show_settings'.tr(), style: context.textTheme.bodyMedium),
              ),
            ],
          ),
        ),
      ),
      actions: actions.map((actionBuilder) => actionBuilder()).toList(),
    );
  }
}

Future<void> showDeveloperOptionsModal({required BuildContext context, Future<void> Function()? onSuccess}) {
  return showDialog(
    context: context,
    barrierDismissible: false,
    builder: (BuildContext context) => DeveloperOptionsModal(onSuccess: onSuccess),
  );
}
