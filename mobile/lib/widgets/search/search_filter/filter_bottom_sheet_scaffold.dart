import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';

class FilterBottomSheetScaffold extends StatelessWidget {
  const FilterBottomSheetScaffold({
    super.key,
    required this.child,
    required this.onSearch,
    required this.onClear,
    required this.title,
    this.expanded,
  });

  final bool? expanded;
  final String title;
  final Widget child;
  final Function() onSearch;
  final Function() onClear;

  @override
  Widget build(BuildContext context) {
    Widget buildChildWidget() {
      if (expanded != null && expanded == true) {
        return Expanded(child: child);
      }
      return Flexible(child: child);
    }

    return AnimatedPadding(
      duration: const Duration(milliseconds: 180),
      curve: Curves.easeOut,
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        top: false,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: MediaQuery.sizeOf(context).height * 0.9),
          child: Column(
            mainAxisSize: MainAxisSize.max,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 12),
                child: Text(title, style: context.textTheme.headlineSmall),
              ),
              buildChildWidget(),
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 8, 8, 12),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    OutlinedButton(
                      onPressed: () {
                        onClear();
                        context.pop();
                      },
                      child: const Text('clear').tr(),
                    ),
                    const SizedBox(width: 8),
                    ElevatedButton(
                      key: const Key('search_filter_apply'),
                      onPressed: () {
                        onSearch();
                        context.pop();
                      },
                      child: const Text('search_filter_apply').tr(),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
