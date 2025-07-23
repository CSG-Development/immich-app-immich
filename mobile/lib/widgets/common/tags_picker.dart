import 'package:collection/collection.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/tag.model.dart';
import 'package:immich_mobile/providers/tags.provider.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

Future<List<Tag>?> showTagsPicker({
  required BuildContext context,
  required WidgetRef ref,
}) async {
  return showDialog<List<Tag>?>(
    context: context,
    builder: (context) => _TagsPicker(ref: ref),
  );
}

class _TagsPicker extends HookConsumerWidget {
  final WidgetRef ref;
  const _TagsPicker({required this.ref});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    useEffect(
      () {
        ref.read(tagsNotifierProvider.notifier).fetchAllTags();
        return null;
      },
      [],
    );

    final allTags = ref.watch(tagsNotifierProvider);
    final selectedTags = useState<Set<Tag>>({});
    final TextEditingController controller = useTextEditingController();

    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
      ),
      title: Text(
        'Add Tag',
        style: context.textTheme.titleLarge,
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            DropdownButton<Tag>(
              isExpanded: true,
              value: null,
              hint: Text(
                'Select existing tag',
                style: context.textTheme.bodyLarge?.copyWith(
                  color: context.colorScheme.onSurfaceVariant,
                ),
              ),
              items: allTags.map((tag) {
                return DropdownMenuItem<Tag>(
                  value: tag,
                  child: Text(
                    tag.name,
                    style: context.textTheme.bodyLarge,
                  ),
                );
              }).toList(),
              onChanged: (tag) {
                if (tag != null) {
                  selectedTags.value = {...selectedTags.value, tag};
                }
              },
              borderRadius: BorderRadius.circular(12),
              dropdownColor: context.colorScheme.surfaceContainerHigh,
            ),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
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
                      onDeleted: () {
                        selectedTags.value =
                            selectedTags.value.where((t) => t != tag).toSet();
                      },
                    ),
                  )
                  .toList(),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              decoration: InputDecoration(
                labelText: 'Or enter new tag',
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
              style: context.textTheme.bodyLarge,
              onSubmitted: (value) {
                final tagName = value.trim();
                if (tagName.isNotEmpty) {
                  final existing =
                      allTags.firstWhereOrNull((t) => t.name == tagName);
                  if (existing != null) {
                    selectedTags.value = {...selectedTags.value, existing};
                  } else {
                    // Will be created on submit
                    selectedTags.value = {
                      ...selectedTags.value,
                      Tag(
                        id: '',
                        name: tagName,
                        value: '',
                        color: null,
                        parentId: null,
                        createdAt: DateTime.now(),
                        updatedAt: DateTime.now(),
                      ),
                    };
                  }
                  controller.clear();
                }
              },
            ),
          ],
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: Text(
            'Cancel',
            style: context.textTheme.bodyLarge?.copyWith(
              color: context.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
        TextButton(
          onPressed: () async {
            final tagsToReturn = <Tag>[];
            for (final tag in selectedTags.value) {
              if (tag.id.isEmpty) {
                // New tag, create it
                final created = await ref
                    .read(tagsNotifierProvider.notifier)
                    .addTag(name: tag.name);
                if (created != null) tagsToReturn.add(created);
              } else {
                tagsToReturn.add(tag);
              }
            }
            Navigator.of(context).pop(tagsToReturn);
          },
          child: Text(
            'Add',
            style: context.textTheme.bodyLarge?.copyWith(
              color: context.primaryColor,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),
      ],
    );
  }
}
