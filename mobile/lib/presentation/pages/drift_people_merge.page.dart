import 'dart:async';

import 'package:auto_route/auto_route.dart';
import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:flutter_svg/svg.dart';
import 'package:fluttertoast/fluttertoast.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/person.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/models/connection_state.model.dart';
import 'package:immich_mobile/presentation/widgets/images/remote_image_provider.dart';
import 'package:immich_mobile/providers/connection_state.provider.dart';
import 'package:immich_mobile/providers/infrastructure/people.provider.dart';
import 'package:immich_mobile/providers/search/people.provider.dart';
import 'package:immich_mobile/utils/image_url_builder.dart';
import 'package:immich_mobile/widgets/common/immich_toast.dart';
import 'package:immich_mobile/widgets/common/search_field.dart';

@RoutePage()
class DriftPeopleMergePage extends HookConsumerWidget {
  final DriftPerson person;

  const DriftPeopleMergePage({super.key, required this.person});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final withClosestPersonId = useState(false);
    final sourcePersonId = useState<String>(person.id);
    final selectedPeopleIds = useState<List<String>>([]);
    final peopleAsync = ref.watch(
      getAllPeopleWithParamsProvider(withClosestPersonId.value ? sourcePersonId.value : null),
    );
    final searchController = useTextEditingController();
    final searchFocus = useFocusNode();
    final searchQuery = useState<String?>(null);
    final isLoadingMerge = useState<bool>(false);

    final peopleParams = withClosestPersonId.value ? sourcePersonId.value : null;
    final allPeople = peopleAsync.value ?? [];
    final isLoading = peopleAsync.isLoading;
    final isError = peopleAsync.error != null;

    void refreshPeopleIfEmpty() {
      final async = ref.read(getAllPeopleWithParamsProvider(peopleParams));
      if (async.isLoading) return;
      if ((async.value ?? []).isNotEmpty) return;
      ref.invalidate(getAllPeopleWithParamsProvider(peopleParams));
    }

    // After recovery the monitor publishes connected — refresh empty list only.
    ref.listen(connectionStateProvider, (prev, next) {
      final stabilized =
          prev?.status != ConnectionStatus.connected && next.status == ConnectionStatus.connected;
      if (!stabilized) return;
      refreshPeopleIfEmpty();
    });

    List<PersonDto> filteredPeople = allPeople.where((p) {
      final matchesSearch =
          searchQuery.value == null || p.name.toLowerCase().contains(searchQuery.value!.toLowerCase());
      final isNotSource = p.id != sourcePersonId.value;
      final isNotSelected = !selectedPeopleIds.value.contains(p.id);

      return matchesSearch && isNotSource && isNotSelected;
    }).toList();

    void onMerge() async {
      try {
        final confirm = await showDialog<bool>(
          context: context,
          builder: (context) => AlertDialog(
            title: Text('confirm'.t()),
            content: Text('merge_people_prompt'.t()),
            actions: [
              TextButton(onPressed: () => Navigator.of(context).pop(false), child: Text('cancel'.t())),
              TextButton(
                onPressed: () => Navigator.of(context).pop(true),
                child: Text('confirm'.t(), style: TextStyle(color: context.colorScheme.error)),
              ),
            ],
          ),
        );

        if (confirm != true) return;

        isLoadingMerge.value = true;

        final mergedPerson = await ref
            .read(driftPeopleServiceProvider)
            .mergePerson(sourcePersonId.value, selectedPeopleIds.value);
        ref.invalidate(driftGetAllPeopleProvider);
        // Return the surviving (target) person so the detail page can switch to
        // it. This matters when the primary face was swapped, otherwise we would
        // pop back to the source person that has just been merged away.
        unawaited(context.maybePop(mergedPerson));

        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (context.mounted) {
            ImmichToast.show(
              context: context,
              msg: 'merged_people_count'.t(context: context, args: {'count': selectedPeopleIds.value.length}),
              gravity: ToastGravity.BOTTOM,
              toastType: ToastType.success,
            );
          }
        });
      } catch (error) {
        if (!context.mounted) {
          return;
        }

        ImmichToast.show(
          context: context,
          msg: 'scaffold_body_error_occurred'.t(),
          gravity: ToastGravity.BOTTOM,
          toastType: ToastType.error,
        );
      } finally {
        isLoadingMerge.value = false;
      }
    }

    void onPersonSelected(String personId) {
      if (selectedPeopleIds.value.length >= 5) {
        ImmichToast.show(
          context: context,
          msg: 'merge_people_limit'.t(),
          gravity: ToastGravity.BOTTOM,
          toastType: ToastType.error,
        );
        return;
      }
      selectedPeopleIds.value = [personId, ...selectedPeopleIds.value];
    }

    void onPersonRemoved(String personId) {
      selectedPeopleIds.value = selectedPeopleIds.value.where((id) => id != personId).toList();
    }

    Widget topWidget() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 12.0),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Text(
              'choose_matching_people_to_merge'.tr().toUpperCase(),
              textAlign: TextAlign.center,
              style: TextStyle(color: context.themeData.colorScheme.onSurface.withAlpha(150), fontSize: 16.0),
            ),
          ),
          const SizedBox(height: 20.0),
          LayoutBuilder(
            builder: (context, constraints) => SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 7.5),
              scrollDirection: Axis.horizontal,
              child: ConstrainedBox(
                constraints: BoxConstraints(minWidth: constraints.maxWidth - 15),
                child: Row(
                  spacing: selectedPeopleIds.value.length == 1 ? 7.5 : 12.0,
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.center,
                  children: [
                    ...selectedPeopleIds.value.map(
                      (personId) => _PersonCard(
                        personId: personId,
                        onTap: () => onPersonRemoved(personId),
                        size: 117.0,
                      ),
                    ),
                    if (selectedPeopleIds.value.isNotEmpty)
                      Column(
                        children: [
                          SvgPicture.asset(
                            'assets/merge-people.svg',
                            height: 48,
                            colorFilter: ColorFilter.mode(context.themeData.colorScheme.onSurface, BlendMode.srcIn),
                          ),
                          if (selectedPeopleIds.value.length == 1)
                            GestureDetector(
                              child: SvgPicture.asset(
                                'assets/merge-people-swap.svg',
                                height: 48,
                                colorFilter: ColorFilter.mode(context.themeData.colorScheme.onSurface, BlendMode.srcIn),
                              ),
                              onTap: () {
                                final prevSourcePersonId = sourcePersonId.value;
                                sourcePersonId.value = selectedPeopleIds.value.first;
                                selectedPeopleIds.value = [prevSourcePersonId];
                              },
                            ),
                        ],
                      ),
                    _PersonCard(personId: sourcePersonId.value, size: 156.0),
                  ],
                ),
              ),
            ),
          ),
        ],
      );
    }

    Widget bottomWidget() {
      return Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(height: 20.0),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12.0),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(
                  child: SearchField(
                    controller: searchController,
                    focusNode: searchFocus,
                    onChanged: (value) => searchQuery.value = value,
                    onTapOutside: (_) => searchFocus.unfocus(),
                    filled: true,
                    hintText: 'search_people'.tr(),
                    autofocus: false,
                    contentPadding: const EdgeInsetsGeometry.fromLTRB(24.0, 14.0, 0.0, 14.0),
                    prefixIcon: const Icon(Icons.search_rounded),
                    suffixIcon: searchQuery.value?.isEmpty == true
                        ? null
                        : IconButton(
                            onPressed: () {
                              searchController.clear();
                              searchQuery.value = null;
                              searchFocus.unfocus();
                            },
                            icon: const Icon(Icons.close_rounded),
                          ),
                  ),
                ),
                const SizedBox(width: 12.0),
                IconButton(
                  icon: SvgPicture.asset(
                    'assets/merge-people-sort.svg',
                    height: 18.0,
                    colorFilter: ColorFilter.mode(context.themeData.colorScheme.onSurface, BlendMode.srcIn),
                  ),
                  onPressed: () {
                    withClosestPersonId.value = !withClosestPersonId.value;
                  },
                ),
              ],
            ),
          ),
          const SizedBox(height: 20.0),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 12.0),
              child: Container(
                decoration: BoxDecoration(
                  borderRadius: const BorderRadius.all(Radius.circular(24.0)),
                  border: Border.all(width: 1.0, color: context.themeData.colorScheme.surfaceDim),
                  color: context.themeData.colorScheme.surfaceContainerLowest,
                ),
                child: isLoading
                    ? const Center(child: CircularProgressIndicator())
                    : isError
                    ? Center(child: Text('error'.tr()))
                    : filteredPeople.isEmpty
                    ? Center(
                        child: Text(
                          'no_people_found'.tr(),
                          style: context.textTheme.bodyLarge?.copyWith(color: context.colorScheme.outline),
                        ),
                      )
                    : GridView.builder(
                        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                          crossAxisCount: _getCrossAxisCount(context),
                          mainAxisSpacing: 32.0,
                          crossAxisSpacing: 32.0,
                        ),
                        padding: const EdgeInsets.symmetric(horizontal: 35.0, vertical: 32.0),
                        itemCount: filteredPeople.length,
                        itemBuilder: (context, index) {
                          final person = filteredPeople[index];
                          return _PersonCard(
                            personId: person.id,
                            onTap: () => onPersonSelected(person.id),
                          );
                        },
                      ),
              ),
            ),
          ),
        ],
      );
    }

    Widget content() {
      final isLandscapeMobile = !context.isTablet && MediaQuery.of(context).orientation == Orientation.landscape;
      if (isLandscapeMobile) {
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              flex: 2,
              child: SingleChildScrollView(padding: const EdgeInsets.only(bottom: 20), child: topWidget()),
            ),
            Container(
              width: 1,
              margin: const EdgeInsets.symmetric(vertical: 20),
              color: context.themeData.colorScheme.surfaceDim,
            ),
            Expanded(flex: 3, child: bottomWidget()),
          ],
        );
      }

      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          topWidget(),
          Expanded(child: bottomWidget()),
        ],
      );
    }

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: true,
        title: Text(
          selectedPeopleIds.value.isNotEmpty
              ? '${selectedPeopleIds.value.length} ${'selected'.tr().toLowerCase()}'
              : 'merge_people'.tr(),
        ),
        titleTextStyle: context.themeData.appBarTheme.titleTextStyle?.copyWith(
          color: context.themeData.colorScheme.onSurface,
        ),
        centerTitle: false,
        leading: IconButton(
          icon: Icon(Icons.close_rounded, color: context.themeData.colorScheme.onSurface),
          onPressed: () {
            context.maybePop(null);
          },
        ),
        actions: [
          Padding(
            padding: const EdgeInsets.only(right: 12.0),
            child: ElevatedButton.icon(
              onPressed: selectedPeopleIds.value.isEmpty || isLoadingMerge.value ? null : onMerge,
              icon: isLoadingMerge.value
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 1.0))
                  : SvgPicture.asset(
                      'assets/merge-people.svg',
                      height: 18,
                      colorFilter: ColorFilter.mode(
                        selectedPeopleIds.value.isEmpty
                            ? context.colorScheme.onSurface.withOpacity(0.38)
                            : context.colorScheme.onPrimary,
                        BlendMode.srcIn,
                      ),
                    ),
              label: Text('merge'.t()),
              style: OutlinedButton.styleFrom(padding: const EdgeInsets.symmetric(vertical: 10.0, horizontal: 24.0)),
            ),
          ),
        ],
      ),
      body: SafeArea(child: content()),
    );
  }

  int _getCrossAxisCount(BuildContext context) {
    if (context.isTablet) {
      return context.orientation == Orientation.portrait ? 4 : 6;
    }
    return 2;
  }
}

class _PersonCard extends StatelessWidget {
  final String personId;
  final VoidCallback? onTap;
  final double? size;

  const _PersonCard({required this.personId, this.onTap, this.size});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final diameter = size ?? constraints.biggest.shortestSide;
          return SizedBox(
            width: diameter,
            height: diameter,
            child: DecoratedBox(
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(width: 1.0, color: context.colorScheme.primary),
              ),
              child: CircleAvatar(
                backgroundImage: RemoteImageProvider(url: getFaceThumbnailUrl(personId)),
              ),
            ),
          );
        },
      ),
    );
  }
}
