import 'package:auto_route/auto_route.dart';
import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/domain/models/person.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/presentation/widgets/people/person_option_sheet.widget.dart';
import 'package:immich_mobile/providers/infrastructure/people.provider.dart';
import 'package:immich_mobile/presentation/widgets/timeline/timeline.widget.dart';
import 'package:immich_mobile/providers/infrastructure/timeline.provider.dart';
import 'package:immich_mobile/providers/user.provider.dart';
import 'package:immich_mobile/routing/router.dart';
import 'package:immich_mobile/utils/people.utils.dart';
import 'package:immich_mobile/widgets/common/person_sliver_app_bar.dart';

@RoutePage()
class DriftPersonPage extends ConsumerStatefulWidget {
  final DriftPerson person;

  const DriftPersonPage({super.key, required this.person});

  @override
  ConsumerState<DriftPersonPage> createState() => _DriftPersonPageState();
}

class _DriftPersonPageState extends ConsumerState<DriftPersonPage> {
  late DriftPerson _person;

  @override
  initState() {
    super.initState();
    _person = widget.person;
  }

  Future<void> handleEditName(BuildContext context) async {
    final newName = await showNameEditModal(context, _person);

    if (newName != null && newName.isNotEmpty) {
      setState(() {
        _person = _person.copyWith(name: newName);
      });
    }
  }

  Future<void> handleEditBirthday(BuildContext context) async {
    final birthday = await showBirthdayEditModal(context, _person);

    if (birthday != null) {
      setState(() {
        _person = _person.copyWith(birthDate: birthday);
      });
    }
  }

  Future<void> handleMerge() async {
    final mergedPerson = await context.pushRoute<DriftPerson?>(DriftPeopleMergeRoute(person: _person));

    // After a merge the surviving (target) person is returned. When the primary
    // face was swapped, this differs from the person we opened (which has just
    // been merged away), so switch the page to the survivor. The ProviderScope
    // below is keyed on the person id, so changing it rebuilds the timeline for
    // the correct person instead of keeping the now-empty source timeline.
    if (mergedPerson != null && mounted) {
      setState(() {
        _person = mergedPerson;
      });
    }
  }

  Future<void> handleToggleFavorite() async {
    final isFavorite = !_person.isFavorite;
    final success = await togglePersonFavorite(
      context: context,
      isFavorite: isFavorite,
      update: () async {
        final result = await ref.read(driftPeopleServiceProvider).updateFavorite(_person.id, isFavorite);
        if (result == 0) {
          throw StateError('Person ${_person.id} was not found in the local database');
        }
      },
    );

    if (!success || !mounted) {
      return;
    }

    setState(() {
      _person = _person.copyWith(isFavorite: isFavorite);
    });
    ref.invalidate(driftGetAllPeopleProvider);
  }

  void showOptionSheet(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: context.colorScheme.surface,
      isScrollControlled: false,
      builder: (context) {
        return PersonOptionSheet(
          onEditName: () async {
            await handleEditName(context);
            context.pop();
          },
          onEditBirthday: () async {
            await handleEditBirthday(context);
            context.pop();
          },
          onMerge: () {
            context.pop();
            handleMerge();
          },
          onToggleFavorite: () {
            context.pop();
            handleToggleFavorite();
          },
          birthdayExists: _person.birthDate != null,
          isFavorite: _person.isFavorite,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    return ProviderScope(
      key: ValueKey(_person.id),
      overrides: [
        timelineServiceProvider.overrideWith((ref) {
          final user = ref.watch(currentUserProvider);
          if (user == null) {
            throw Exception('User must be logged in to view person timeline');
          }

          final timelineService = ref.watch(timelineFactoryProvider).person(user.id, _person.id);
          ref.onDispose(timelineService.dispose);
          return timelineService;
        }),
      ],
      child: Timeline(
        appBar: PersonSliverAppBar(
          person: _person,
          onNameTap: () => handleEditName(context),
          onBirthdayTap: () => handleEditBirthday(context),
          onShowOptions: () => showOptionSheet(context),
        ),
      ),
    );
  }
}
