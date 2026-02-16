import 'package:flutter/material.dart';
import 'package:flutter_svg/svg.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';

class PersonOptionSheet extends ConsumerWidget {
  const PersonOptionSheet({super.key, this.onEditName, this.onEditBirthday, this.onMerge, this.birthdayExists = false});

  final VoidCallback? onEditName;
  final VoidCallback? onEditBirthday;
  final VoidCallback? onMerge;
  final bool birthdayExists;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    TextStyle textStyle = Theme.of(context).textTheme.bodyLarge!.copyWith(fontWeight: FontWeight.w600);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 24.0),
        child: ListView(
          shrinkWrap: true,
          children: [
            ListTile(
              leading: const Icon(Icons.edit),
              title: Text('edit_name'.t(context: context), style: textStyle),
              onTap: onEditName,
            ),
            ListTile(
              leading: const Icon(Icons.cake),
              title: Text((birthdayExists ? 'edit_birthday' : "add_birthday").t(context: context), style: textStyle),
              onTap: onEditBirthday,
            ),
            ListTile(
              leading: SizedBox(
                width: 24.0,
                height: 24.0,
                child: Center(
                  child: SvgPicture.asset(
                    'assets/merge-people-menu-item.svg',
                    colorFilter: ColorFilter.mode(context.colorScheme.onSurface, BlendMode.srcIn),
                  ),
                ),
              ),
              title: Text(("merge_people").t(context: context), style: textStyle),
              onTap: onMerge,
            ),
          ],
        ),
      ),
    );
  }
}
