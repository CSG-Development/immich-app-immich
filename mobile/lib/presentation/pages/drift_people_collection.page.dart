import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/person.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/people/person_option_sheet.widget.dart';
import 'package:immich_mobile/extensions/string_extensions.dart';
import 'package:immich_mobile/providers/infrastructure/people.provider.dart';
import 'package:immich_mobile/presentation/widgets/images/remote_image_provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/image_url_builder.dart';
import 'package:immich_mobile/utils/people.utils.dart';
import 'package:immich_mobile/widgets/common/search_field.dart';

@RoutePage()
class DriftPeopleCollectionPage extends ConsumerStatefulWidget {
  const DriftPeopleCollectionPage({super.key});

  @override
  ConsumerState<DriftPeopleCollectionPage> createState() => _DriftPeopleCollectionPageState();
}

class _DriftPeopleCollectionPageState extends ConsumerState<DriftPeopleCollectionPage> {
  final FocusNode _formFocus = FocusNode();
  String? _search;

  @override
  void dispose() {
    _formFocus.dispose();
    super.dispose();
  }

  Future<void> _toggleFavorite(DriftPerson person) async {
    final isFavorite = !person.isFavorite;
    final success = await togglePersonFavorite(
      context: context,
      isFavorite: isFavorite,
      update: () async {
        final result = await ref.read(driftPeopleServiceProvider).updateFavorite(person.id, isFavorite);
        if (result == 0) {
          throw StateError('Person ${person.id} was not found in the local database');
        }
      },
    );

    if (success) {
      ref.invalidate(driftGetAllPeopleProvider);
    }
  }

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(driftGetAllPeopleProvider);

    return LayoutBuilder(
      builder: (context, constraints) {
        final isTablet = context.isTablet;
        final isPortrait = context.orientation == Orientation.portrait;

        return Scaffold(
          appBar: AppBar(
            automaticallyImplyLeading: _search == null,
            title: _search != null
                ? SearchField(
                    focusNode: _formFocus,
                    onTapOutside: (_) => _formFocus.unfocus(),
                    onChanged: (value) => setState(() => _search = value),
                    filled: true,
                    hintText: 'filter_people'.tr(),
                    autofocus: true,
                  )
                : Text('people'.tr()),
            actions: [
              IconButton(
                icon: Icon(_search != null ? Icons.close : Icons.search),
                onPressed: () {
                  setState(() => _search = _search == null ? '' : null);
                },
              ),
            ],
          ),
          body: SafeArea(
            child: people.when(
              skipLoadingOnReload: true,
              data: (people) {
                if (_search != null) {
                  people = people.where((person) {
                    return person.name.toLowerCase().removeDiacritics().contains(
                      _search!.toLowerCase().removeDiacritics(),
                    );
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
                      key: ValueKey(person.id),
                      children: [
                        Stack(
                          alignment: Alignment.center,
                          children: [
                            GestureDetector(
                              onTap: () {
                                context.pushRoute(DriftPersonRoute(person: person));
                              },
                              child: Material(
                                shape: const CircleBorder(side: BorderSide.none),
                                elevation: 3,
                                child: CircleAvatar(
                                  key: ValueKey(person.id),
                                  maxRadius: isTablet ? 100 / 2 : 96 / 2,
                                  backgroundImage: RemoteImageProvider(url: getFaceThumbnailUrl(person.id)),
                                ),
                              ),
                            ),
                            if (person.isFavorite)
                              Positioned(
                                left: 8,
                                top: 8,
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
                              right: 0.0,
                              top: 0.0,
                              child: IconButton(
                                icon: Container(
                                  decoration: BoxDecoration(
                                    color: Theme.of(context).brightness == Brightness.dark
                                        ? Colors.black.withValues(alpha: 0.7)
                                        : context.colorScheme.surfaceContainer,
                                    shape: BoxShape.circle,
                                  ),
                                  child: const SizedBox(
                                    width: 40.0,
                                    height: 40.0,
                                    child: Icon(Icons.more_vert, size: 24),
                                  ),
                                ),
                                onPressed: () {
                                  showModalBottomSheet(
                                    context: context,
                                    backgroundColor: context.colorScheme.surface,
                                    builder: (sheetContext) {
                                      return PersonOptionSheet(
                                        onEditName: () {
                                          Navigator.of(sheetContext).pop();
                                          showNameEditModal(sheetContext, person);
                                        },
                                        onEditBirthday: () {
                                          Navigator.of(sheetContext).pop();
                                          showBirthdayEditModal(sheetContext, person);
                                        },
                                        onMerge: () {
                                          Navigator.of(sheetContext).pop();
                                          sheetContext.pushRoute(DriftPeopleMergeRoute(person: person));
                                        },
                                        onToggleFavorite: () {
                                          Navigator.of(sheetContext).pop();
                                          _toggleFavorite(person);
                                        },
                                        birthdayExists: person.birthDate != null,
                                        isFavorite: person.isFavorite,
                                      );
                                    },
                                  );
                                },
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                        GestureDetector(
                          onTap: () => showNameEditModal(context, person),
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
