import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:homecloud_frontend/api/api.swagger.dart';
import 'package:immich_mobile/widgets/forms/login/server_endpoint_input.dart';

class DeviceItem {
  final Uri? baseUrl;
  final About? about;
  final Status? status;
  final bool isTemporary;

  DeviceItem({this.baseUrl, this.about, this.status, this.isTemporary = false});

  String get name => isTemporary
      ? baseUrl.toString()
      : about?.hostname.isNotEmpty == true
      ? about!.hostname
      : baseUrl?.host ?? 'Unknown Device';

  bool get isReady => status == null || status!.state == StatusState.ready;

  String warnStatus(BuildContext context) {
    if (isReady) return "";
    return " (dashboard_device_card_device_status(status!.state.name))";
  }
}

class DeviceSelector extends HookWidget {
  final List devices;
  final dynamic selectedDevice;
  final bool isDetecting;
  final ValueChanged<dynamic> onDeviceSelected;
  final VoidCallback onRefresh;
  final FocusNode? focusNode;
  final double? maxWidth;
  final bool enabled;
  final TextEditingController controller;

  const DeviceSelector({
    super.key,
    required this.devices,
    required this.selectedDevice,
    this.isDetecting = false,
    required this.onDeviceSelected,
    required this.onRefresh,
    this.focusNode,
    this.maxWidth,
    this.enabled = true,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    final manualInputDevice = useState<DeviceItem?>(null);
    final isDropdownOpen = useState<bool>(false);

    // Use useEffect to handle controller text updates
    useEffect(() {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!context.mounted) return;
        final DeviceItem? selected = selectedDevice is DeviceItem ? selectedDevice as DeviceItem : null;
        final String text = selected?.name ?? '';
        if (controller.text != text) {
          controller.value = controller.value.copyWith(
            text: text,
            selection: TextSelection.collapsed(offset: text.length),
            composing: TextRange.empty,
          );
        }
      });
      return null;
    }, [selectedDevice]);

    // Track focus changes to update dropdown state
    useEffect(() {
      if (focusNode == null) return null;
      
      void onFocusChange() {
        if (!focusNode!.hasFocus) {
          isDropdownOpen.value = false;
        }
      }
      
      focusNode!.addListener(onFocusChange);
      return () => focusNode!.removeListener(onFocusChange);
    }, [focusNode]);

    Widget buildIconDevice(DeviceItem? device) {
      late Widget icon;
      if (device == null) {
        if (isDetecting) {
          icon = const Icon(Icons.search, size: 32);
        } else {
          icon = const Icon(Icons.cloud_off, size: 32, color: Colors.red);
        }
      } else {
        icon = Image.asset("assets/device.webp", width: 50, height: 40);
      }
      return SizedBox(height: 40.0, width: 50.0, child: icon);
    }

    List<DeviceItem> getFilteredOptions(String input) {
      final List<DeviceItem> items = devices.cast<DeviceItem>();
      final filteredItems = input.isEmpty
          ? items
          : items.where((device) => device.name.toLowerCase().contains(input.toLowerCase())).toList();

      // Check if manual input should be added
      if (input.isNotEmpty) {
        final exists = items.any((device) => device.name.toLowerCase() == input.toLowerCase());
        if (!exists) {
          // Create temporary device for manual input
          final manualDevice = DeviceItem(baseUrl: Uri.tryParse(input), isTemporary: true);
          manualInputDevice.value = manualDevice;
          return [...filteredItems, manualDevice];
        } else {
          manualInputDevice.value = null;
        }
      } else {
        manualInputDevice.value = null;
      }

      return filteredItems;
    }

    void onOptionSelected(DeviceItem value) {
      controller.text = value.name;
      onDeviceSelected(value);
      // Clear temporary device after selection
      if (value.isTemporary) {
        manualInputDevice.value = null;
      }
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.end,
      crossAxisAlignment: CrossAxisAlignment.start,
      spacing: 12,
      children: [
        Expanded(
          child: LayoutBuilder(
            builder: (BuildContext context, BoxConstraints constraints) {
              final double maxWidth = constraints.maxWidth;
              return RawAutocomplete<DeviceItem>(
                textEditingController: controller,
                focusNode: focusNode,
                optionsBuilder: (value) {
                  final input = value.text.trim();
                  final options = getFilteredOptions(input);
                  // Update dropdown state based on whether options are available and field has focus
                  WidgetsBinding.instance.addPostFrameCallback((_) {
                    isDropdownOpen.value = options.isNotEmpty && (focusNode?.hasFocus ?? false);
                  });
                  return options;
                },
                displayStringForOption: (value) => value.name,
                onSelected: (option) {
                  isDropdownOpen.value = false;
                  onOptionSelected(option);
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return ServerEndpointInput(
                    label: isDetecting
                        ? 'curator.oobe_welcome_dropdown_detecting'.tr()
                        : 'curator.sign_in_screen_dropdown_device_label'.tr(),
                    controller: controller,
                    focusNode: focusNode,
                    leadingIcon: Padding(
                      padding: const EdgeInsets.only(left: 8.0),
                      child: buildIconDevice(selectedDevice),
                    ),
                    suffixIcon: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                      icon: Icon(
                        isDropdownOpen.value ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down,
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      onPressed: () {
                        if (focusNode.hasFocus && isDropdownOpen.value) {
                          focusNode.unfocus();
                          isDropdownOpen.value = false;
                        } else {
                          focusNode.requestFocus();
                          // Trigger optionsBuilder by notifying listeners
                          controller.value = controller.value.copyWith(
                            text: controller.text,
                            selection: TextSelection.collapsed(offset: controller.text.length),
                            composing: TextRange.empty,
                          );
                        }
                      },
                    ),
                    onSubmit: () {
                      if (controller.text.isEmpty) {
                        onDeviceSelected(null);
                      } else {
                        onFieldSubmitted();
                      }
                    },
                  );
                },
                optionsViewBuilder: (context, onSelected, options) {
                  return Align(
                    alignment: Alignment.topLeft,
                    child: Material(
                      elevation: 4,
                      borderRadius: BorderRadius.circular(12),
                      clipBehavior: Clip.antiAlias,
                      child: ConstrainedBox(
                        constraints: BoxConstraints(maxHeight: 300, minWidth: maxWidth, maxWidth: maxWidth),
                        child: ListView.builder(
                          padding: EdgeInsets.zero,
                          shrinkWrap: true,
                          itemCount: options.length,
                          itemBuilder: (_, index) {
                            final option = options.elementAt(index);
                            return ListTile(
                              leading: option.isTemporary ? const Icon(Icons.add) : buildIconDevice(option),
                              title: Text(option.isTemporary ? option.name : option.name + option.warnStatus(context)),
                              onTap: () {
                                onSelected(option);
                              },
                            );
                          },
                        ),
                      ),
                    ),
                  );
                },
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(top: 16.0),
          child: SizedBox(
            height: 24.0,
            width: 24.0,
            child: isDetecting
                ? const CircularProgressIndicator.adaptive()
                : IconButton(icon: const Icon(Icons.refresh), padding: EdgeInsets.zero, onPressed: onRefresh),
          ),
        ),
      ],
    );
  }
}
