import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:homecloud_frontend/homecloud_frontend.dart' show DeviceItem;
import 'package:immich_mobile/widgets/forms/login/server_endpoint_input.dart';

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

    Widget? buildIconDevice(DeviceItem? device) {
      late Widget? icon;
      if (device == null) {
        if (isDetecting) {
          icon = const Icon(Icons.search, size: 32);
        } else {
          // icon = const Icon(Icons.cloud_off, size: 32, color: Colors.red);
          icon = null;
        }
      } else {
        icon = Image.asset("assets/device.webp", width: 50, height: 40);
      }
      return icon != null
          ? Padding(
              padding: const EdgeInsets.only(left: 8.0),
              child: SizedBox(height: 40.0, width: 50.0, child: icon),
            )
          : null;
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
          // Defer state update to avoid setState during build
          WidgetsBinding.instance.addPostFrameCallback((_) {
            manualInputDevice.value = manualDevice;
          });
          return [...filteredItems, manualDevice];
        } else {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            manualInputDevice.value = null;
          });
        }
      } else {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          manualInputDevice.value = null;
        });
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
                  return [...options, DeviceItem()];
                },
                displayStringForOption: (value) => value.name,
                onSelected: (option) {
                  isDropdownOpen.value = false;
                  onOptionSelected(option);
                },
                fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
                  return ServerEndpointInput(
                    label: 'curator.sign_in_screen_dropdown_device_label'.tr(),
                    controller: controller,
                    focusNode: focusNode,
                    leadingIcon: buildIconDevice(selectedDevice),
                    isDetecting: isDetecting,
                    isEmpty: getFilteredOptions(controller.text).isEmpty,
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
                            return option.baseUrl != null
                                ? ListTile(
                                    title: Text(option.name),
                                    onTap: () {
                                      onSelected(option);
                                    },
                                  )
                                : Column(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      index > 0 ? const Divider(height: 1) : const SizedBox.shrink(),
                                      const ListTile(title: Text('I don’t see my Curator')),
                                    ],
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
                ? const CircularProgressIndicator()
                : IconButton(
                    icon: Icon(Icons.refresh, color: Theme.of(context).primaryColor),
                    padding: EdgeInsets.zero,
                    onPressed: onRefresh,
                  ),
          ),
        ),
      ],
    );
  }
}
