import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/people/person_option_sheet.widget.dart';
import 'package:immich_mobile/providers/infrastructure/people.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/services/api.service.dart';
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

  @override
  Widget build(BuildContext context) {
    final people = ref.watch(driftGetAllPeopleProvider);
    final headers = ApiService.getRequestHeaders();

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
              data: (people) {
                if (_search != null) {
                  people = people.where((person) {
                    return person.name.toLowerCase().contains(_search!.toLowerCase());
                  }).toList();
                }
                return GridView.builder(
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isTablet ? 4 : 2,
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
                          children: [
                            GestureDetector(
                              onTap: () {
                                context.pushRoute(DriftPersonRoute(person: person));
                              },
                              child: Material(
                                shape: const CircleBorder(side: BorderSide.none),
                                elevation: 3,
                                child: CircleAvatar(
                                  maxRadius: 156 / 2,
                                  backgroundImage: NetworkImage(getFaceThumbnailUrl(person.id), headers: headers),
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
                                          sheetContext.pop();
                                          showNameEditModal(sheetContext, person);
                                        },
                                        onEditBirthday: () {
                                          sheetContext.pop();
                                          showBirthdayEditModal(sheetContext, person);
                                        },
                                        onMerge: () {
                                          sheetContext.pop();
                                          sheetContext.pushRoute(DriftPeopleMergeRoute(person: person));
                                        },
                                        birthdayExists: person.birthDate != null,
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
