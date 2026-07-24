import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/person.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/people/person_option_sheet.widget.dart';
import 'package:immich_mobile/providers/search/people.provider.dart';
import 'package:immich_mobile/presentation/widgets/images/remote_image_provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/person.service.dart';
import 'package:immich_mobile/utils/image_url_builder.dart';
import 'package:immich_mobile/utils/people.utils.dart';
import 'package:immich_mobile/widgets/common/search_field.dart';
import 'package:immich_mobile/widgets/search/person_name_edit_form.dart';

@RoutePage()
class PeopleCollectionPage extends HookConsumerWidget {
  const PeopleCollectionPage({super.key});
  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final people = ref.watch(getAllPeopleProvider);
    final formFocus = useFocusNode();
    final ValueNotifier<String?> search = useState(null);

    showNameEditModel(String personId, String personName) {
      return showDialog(
        context: context,
        useRootNavigator: false,
        builder: (BuildContext context) {
          return PersonNameEditForm(personId: personId, personName: personName);
        },
      );
    }

    Future<void> toggleFavorite(PersonDto person) async {
      final isFavorite = !person.isFavorite;
      final success = await togglePersonFavorite(
        context: context,
        isFavorite: isFavorite,
        update: () async {
          final updatedPerson = await ref.read(personServiceProvider).updateFavorite(person.id, isFavorite);
          if (updatedPerson == null || updatedPerson.isFavorite != isFavorite) {
            throw StateError('Failed to update favorite for person ${person.id}');
          }
        },
      );

      if (success) {
        ref.invalidate(getAllPeopleProvider);
      }
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = context.isTablet;
        final isPortrait = context.orientation == Orientation.portrait;

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: search.value == null,
            title: search.value != null
                ? SearchField(
                    focusNode: formFocus,
                    onTapOutside: (_) => formFocus.unfocus(),
                    onChanged: (value) => search.value = value,
                    filled: true,
                    hintText: 'filter_people'.tr(),
                    autofocus: true,
                  )
                : Text('people'.tr()),
            actions: [
              IconButton(
                icon: Icon(search.value != null ? Icons.close : Icons.search),
                onPressed: () {
                  search.value = search.value == null ? '' : null;
                },
              ),
            ],
          ),
          body: SafeArea(
            child: people.when(
              skipLoadingOnReload: true,
              data: (people) {
                if (search.value != null) {
                  people = people.where((person) {
                    return person.name.toLowerCase().contains(search.value!.toLowerCase());
                  }).toList();
                }
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isTablet ? 6 : 3,
                    childAspectRatio: 0.85,
                    mainAxisSpacing: isPortrait && isTablet ? 36 : 0,
                  ),
                  padding: const EdgeInsets.symmetric(vertical: 32),
                  itemCount: people.length,
                  itemBuilder: (context, index) {
                    final person = people[index];

                    return Column(
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {
                                context.pushRoute(PersonResultRoute(personId: person.id, personName: person.name));
                              },
                              child: Material(
                                shape: const CircleBorder(side: BorderSide.none),
                                elevation: 3,
                                child: CircleAvatar(
                                  maxRadius: isTablet ? 120 / 2 : 96 / 2,
                                  backgroundImage: RemoteImageProvider(url: getFaceThumbnailUrl(person.id)),
                                ),
                              ),
                            ),
                            if (person.isFavorite)
                              Positioned(
                                left: 0,
                                top: 0,
                                child: IgnorePointer(
                                  child: Container(
                                    padding: const EdgeInsets.all(6),
                                    decoration: BoxDecoration(
                                      color: context.colorScheme.surfaceContainer.withValues(alpha: 0.9),
                                      shape: BoxShape.circle,
                                    ),
                                    child: Icon(Icons.favorite, size: 20, color: context.colorScheme.primary),
                                  ),
                                ),
                              ),
                            Positioned(
                              right: 0,
                              top: 0,
                              child: IconButton(
                                icon: const Icon(Icons.more_vert),
                                onPressed: () {
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: context.colorScheme.surface,
                                    builder: (sheetContext) => PersonOptionSheet(
                                      onEditName: () {
                                        sheetContext.pop();
                                        showNameEditModel(person.id, person.name);
                                      },
                                      onToggleFavorite: () {
                                        sheetContext.pop();
                                        toggleFavorite(person);
                                      },
                                      isFavorite: person.isFavorite,
                                    ),
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => showNameEditModel(person.id, person.name),
                          child: person.name.isEmpty
                              ? Text(
                                  'add_a_name'.tr(),
                                  style: context.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.w500,
                                    color: context.colorScheme.primary,
                                  ),
                                )
                              : Padding(
                                  padding: const EdgeInsets.symmetric(horizontal: 16.0),
                                  child: Text(
                                    person.name,
                                    overflow: TextOverflow.ellipsis,
                                    style: context.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w500),
                                  ),
                                ),
                        ),
                      ],
                    );
                  },
                );
              },
              error: (error, stack) => const Text("error"),
              loading: () => const Center(child: CircularProgressIndicator()),
            ),
          ),
        );
      },
    );
  }
}
