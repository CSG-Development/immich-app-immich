import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/models/search/search_filter.model.dart';
import 'package:immich_mobile/providers/search/search_filter.provider.dart';
import 'package:immich_mobile/widgets/search/search_filter/common/dropdown.dart';
import 'package:openapi/api.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:fluttertoast/fluttertoast.dart';

class CameraPicker extends HookConsumerWidget {
  const CameraPicker({super.key, required this.onSelect, this.filter});

  final Function(Map<String, String?>) onSelect;
  final SearchCameraFilter? filter;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final makeTextController = useTextEditingController(text: filter?.make);
    final modelTextController = useTextEditingController(text: filter?.model);
    final selectedMake = useState<String?>(filter?.make);
    final selectedModel = useState<String?>(filter?.model);

    // Cache last non-empty values to avoid empty dropdowns during loading
    final cachedMakeOptions = useState<List<String>>(<String>[]);
    final cachedModelOptions = useState<List<String>>(<String>[]);

    final make = ref.watch(
      getSearchSuggestionsProvider(
        SearchSuggestionType.cameraMake,
      ),
    );

    final models = ref.watch(getSearchSuggestionsProvider(SearchSuggestionType.cameraModel, make: selectedMake.value));

    // Show error toast if make suggestions fail to load
    final makeErrorToastShown = useState<bool>(false);
    useEffect(() {
      if (make case AsyncError()) {
        if (!makeErrorToastShown.value) {
          makeErrorToastShown.value = true;
          ImmichToast.show(
            context: context,
            msg: 'Failed to load camera makes',
            toastType: ToastType.error,
            gravity: ToastGravity.BOTTOM,
          );
        }
      }
      return null;
    }, [make]);

    // Show error toast if model suggestions fail to load
    final modelErrorToastShown = useState<bool>(false);
    useEffect(() {
      if (models case AsyncError()) {
        if (!modelErrorToastShown.value) {
          modelErrorToastShown.value = true;
          ImmichToast.show(
            context: context,
            msg: 'Failed to load camera models',
            toastType: ToastType.error,
            gravity: ToastGravity.BOTTOM,
          );
        }
      }
      return null;
    }, [models]);

    // Update caches when new data arrives
    useEffect(
      () {
        if (make case AsyncData<List<String>>(:final value)) {
          if (value.isNotEmpty) {
            cachedMakeOptions.value = value;
          }
        }
        return null;
      },
      [make],
    );

    useEffect(
      () {
        if (models case AsyncData<List<String>>(:final value)) {
          if (value.isNotEmpty) {
            cachedModelOptions.value = value;
          }
        }
        return null;
      },
      [models],
    );

    final makeEntries = switch (make) {
      AsyncData(:final value) when value.isNotEmpty => value,
      _ => cachedMakeOptions.value,
    };

    final makeWidget = SearchDropdown(
      dropdownMenuEntries: makeEntries
          .map(
            (e) => DropdownMenuEntry(
              value: e,
              label: e,
            ),
          )
          .toList(),
      label: const Text('make').tr(),
      controller: makeTextController,
      leadingIcon: const Icon(Icons.photo_camera_rounded),
      onSelected: (value) {
        if (value.toString() == selectedMake.value) {
          return;
        }
        selectedMake.value = value.toString();
        modelTextController.value = TextEditingValue.empty;
        cachedModelOptions.value = <String>[];
        onSelect({
          'make': selectedMake.value,
          'model': null,
        });
      },
    );

    final modelEntries = switch (models) {
      AsyncData(:final value) when value.isNotEmpty => value,
      _ => cachedModelOptions.value,
    };

    final modelWidget = SearchDropdown(
      dropdownMenuEntries: modelEntries
          .map(
            (e) => DropdownMenuEntry(
              value: e,
              label: e,
            ),
          )
          .toList(),
      label: const Text('model').tr(),
      controller: modelTextController,
      leadingIcon: const Icon(Icons.camera),
      onSelected: (value) {
        selectedModel.value = value.toString();
        onSelect({'make': selectedMake.value, 'model': selectedModel.value});
      },
    );

    if (context.isMobile) {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          makeWidget,
          const SizedBox(height: 8),
          modelWidget,
        ],
      );
    }

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceEvenly,
      children: [
        Expanded(child: makeWidget),
        const SizedBox(width: 16),
        Expanded(child: modelWidget),
      ],
    );
  }
}
