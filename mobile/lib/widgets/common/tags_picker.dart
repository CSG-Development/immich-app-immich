import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/tag.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/providers/tags.provider.dart';

Future<List<Tag>?> showTagsPicker({
  required BuildContext context,
  required WidgetRef ref,
}) =>
    showDialog<List<Tag>?>(
      context: context,
      builder: (context) => _TagsPicker(ref: ref),
    );

class _TagsPicker extends HookConsumerWidget {
  final WidgetRef ref;
  static const double _maxDropdownHeight = 200;

  const _TagsPicker({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final tagsAsync = ref.watch(tagsNotifierProvider);

    final isLoading = tagsAsync.isLoading;
    final allTags = tagsAsync.value ?? [];

    final searchController = useTextEditingController();
    final searchFocusNode = useFocusNode();
    final fieldKey = useMemoized(() => GlobalKey());

    final availableOptions = useState<List<Tag>>(List.from(allTags));
    final filteredOptions = useState<List<Tag>>(List.from(allTags));
    final selectedTags = useState<List<Tag>>([]);

    useEffect(
      () {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          ref.read(tagsNotifierProvider.notifier).fetchAllTags();
        });
        return null;
      },
      [],
    );

    useEffect(
      () {
        availableOptions.value = List.from(allTags);
        filteredOptions.value = List.from(allTags);
        return null;
      },
      [allTags],
    );

    useEffect(
      () {
        void listener() {
          if (searchFocusNode.hasFocus && !isLoading) {
            _filterOptions('', availableOptions, filteredOptions);
          }
        }

        searchFocusNode.addListener(listener);
        return () => searchFocusNode.removeListener(listener);
      },
      [searchFocusNode, isLoading],
    );

    void addTag(Tag tag) {
      if (!selectedTags.value.any((t) => t.name == tag.name)) {
        selectedTags.value = [...selectedTags.value, tag];
      }
      if (!availableOptions.value.any((t) => t.name == tag.name)) {
        availableOptions.value = [...availableOptions.value, tag];
      }
      searchController.clear();
      FocusScope.of(context).unfocus();
      _filterOptions('', availableOptions, filteredOptions);
    }

    void removeTag(Tag tag) {
      selectedTags.value =
          selectedTags.value.where((t) => t.name != tag.name).toList();
    }

    double getFieldWidth() {
      final renderBox =
          fieldKey.currentContext?.findRenderObject() as RenderBox?;
      return renderBox?.size.width ?? 200;
    }

    Widget buildSearchField() {
      return RawAutocomplete<Tag>(
        textEditingController: searchController,
        focusNode: searchFocusNode,
        optionsBuilder: (value) {
          if (isLoading) return const Iterable<Tag>.empty();

          final input = value.text.trim();
          final allOptions = [...filteredOptions.value];

          if (input.isNotEmpty &&
              !availableOptions.value
                  .any((t) => t.name.toLowerCase() == input.toLowerCase())) {
            allOptions.insert(
              0,
              Tag(
                id: '',
                name: input,
                value: '',
                color: null,
                parentId: null,
                createdAt: DateTime.now(),
                updatedAt: DateTime.now(),
              ),
            );
          }

          return allOptions.where(
            (option) => option.name.toLowerCase().contains(input.toLowerCase()),
          );
        },
        displayStringForOption: (tag) => tag.name,
        onSelected: addTag,
        fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
          return Container(
            key: fieldKey,
            child: TextField(
              controller: controller,
              focusNode: focusNode,
              decoration: InputDecoration(
                hintText:
                    isLoading ? 'Loading tags...' : 'Search or create tag',
                prefixIcon: isLoading
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : const Icon(Icons.search),
                labelStyle: context.textTheme.bodyLarge?.copyWith(
                  color: context.colorScheme.primary,
                ),
                filled: true,
                fillColor: context.colorScheme.surfaceContainerHigh,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(
                    color: context.colorScheme.surfaceDim,
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(
                    color: context.colorScheme.surfaceContainer,
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(25),
                  borderSide: BorderSide(
                    color: context.colorScheme.primary.withAlpha(100),
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  vertical: 12,
                  horizontal: 20,
                ),
              ),
              onChanged: (q) =>
                  _filterOptions(q, availableOptions, filteredOptions),
              onSubmitted: (value) {
                if (value.trim().isNotEmpty) {
                  final newTag = Tag(
                    id: '',
                    name: value.trim(),
                    value: '',
                    color: null,
                    parentId: null,
                    createdAt: DateTime.now(),
                    updatedAt: DateTime.now(),
                  );
                  addTag(newTag);
                }
              },
              enabled: !isLoading,
            ),
          );
        },
        optionsViewBuilder: (context, onSelected, options) {
          return Align(
            alignment: Alignment.topLeft,
            child: Material(
              elevation: 4,
              child: ConstrainedBox(
                constraints: BoxConstraints(
                  maxHeight: _maxDropdownHeight,
                  minWidth: getFieldWidth(),
                  maxWidth: getFieldWidth(),
                ),
                child: ListView.builder(
                  padding: EdgeInsets.zero,
                  shrinkWrap: true,
                  itemCount: options.length,
                  itemBuilder: (_, index) {
                    final option = options.elementAt(index);
                    return ListTile(
                      title: Text(option.name),
                      onTap: () {
                        addTag(option);
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
    }

    Widget buildSelectedTags() {
      if (selectedTags.value.isEmpty) return const SizedBox.shrink();

      return Wrap(
        spacing: 8,
        children: selectedTags.value
            .map(
              (tag) => Chip(
                label: Text(
                  tag.name,
                  style: context.textTheme.labelLarge?.copyWith(
                    color: context.colorScheme.onPrimary,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                backgroundColor: context.colorScheme.primary,
                shape: const StadiumBorder(),
                deleteIcon: Icon(
                  Icons.close,
                  color: context.colorScheme.onPrimary,
                  size: 20,
                ),
                onDeleted: () => removeTag(tag),
              ),
            )
            .toList(),
      );
    }

    Widget buildDialogContent() {
      if (isLoading && allTags.isEmpty) {
        return const SizedBox(
          height: 80,
          child: Center(
            child: SizedBox(
              height: 40,
              width: 40,
              child: CircularProgressIndicator(),
            ),
          ),
        );
      }

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          buildSearchField(),
          const SizedBox(height: 12),
          buildSelectedTags(),
        ],
      );
    }

    List<Widget> buildActions() {
      return [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        const SizedBox(width: 8),
        ElevatedButton(
          onPressed: isLoading
              ? null
              : () async {
                  final tagsToReturn = <Tag>[];
                  for (final tag in selectedTags.value) {
                    if (tag.id.isEmpty) {
                      final created = await ref
                          .read(tagsNotifierProvider.notifier)
                          .addTag(name: tag.name);
                      if (created != null) tagsToReturn.add(created);
                    } else {
                      tagsToReturn.add(tag);
                    }
                  }
                  Navigator.pop(context, tagsToReturn);
                },
          child: const Text('Add Tags'),
        ),
      ];
    }

    Widget buildActionBar() {
      return Container(
        color: Theme.of(context).colorScheme.surface,
        padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: buildActions(),
        ),
      );
    }

    Widget buildLandscapeDialog() {
      return Dialog(
        insetPadding: EdgeInsets.zero,
        child: SafeArea(
          child: GestureDetector(
            onTap: () => FocusScope.of(context).unfocus(),
            child: Scaffold(
              appBar: AppBar(
                title: const Text('Add Tags'),
                leading: IconButton(
                  icon: const Icon(Icons.close),
                  onPressed: () => Navigator.pop(context),
                ),
              ),
              body: Column(
                children: [
                  Expanded(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.all(16),
                      child: buildDialogContent(),
                    ),
                  ),
                  buildActionBar(),
                ],
              ),
            ),
          ),
        ),
      );
    }

    Widget buildPortraitDialog() {
      return GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        child: AlertDialog(
          title: const Text('Add Tags'),
          content: ConstrainedBox(
            constraints: const BoxConstraints(
              maxWidth: 400,
            ),
            child: buildDialogContent(),
          ),
          actions: buildActions(),
          insetPadding: const EdgeInsets.symmetric(horizontal: 40.0),
        ),
      );
    }

    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;
    return isLandscape ? buildLandscapeDialog() : buildPortraitDialog();
  }

  static void _filterOptions(
    String query,
    ValueNotifier<List<Tag>> available,
    ValueNotifier<List<Tag>> filtered,
  ) {
    if (query.isEmpty) {
      filtered.value = List.from(available.value);
    } else {
      filtered.value = available.value
          .where(
            (option) => option.name.toLowerCase().contains(query.toLowerCase()),
          )
          .toList();
    }
  }
}
