import 'dart:async';

import 'package:easy_localization/easy_localization.dart';
import 'package:flutter/material.dart';
import 'package:flutter_hooks/flutter_hooks.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:immich_mobile/constants/colors.dart';
import 'package:immich_mobile/constants/locales.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/services/localization.service.dart';
import 'package:immich_mobile/theme/theme_data.dart';
import 'package:immich_mobile/widgets/common/search_field.dart';

bool _isSgTheme(BuildContext context) {
  final chrome = Theme.of(context).extension<ImmichBrandColors>()?.chromeSurface;
  return chrome == sgChromeSurfaceLight || chrome == sgChromeSurfaceDark;
}

class LanguageSettings extends HookConsumerWidget {
  const LanguageSettings({super.key});

  Future<void> _applyLanguageChange(
    BuildContext context,
    ValueNotifier<Locale> selectedLocale,
    ValueNotifier<bool> isLoading,
  ) async {
    isLoading.value = true;
    await Future.delayed(const Duration(milliseconds: 500));
    try {
      await context.setLocale(selectedLocale.value);
      await loadTranslations();
    } finally {
      isLoading.value = false;
    }
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final localeEntries = useMemoized(() => locales.entries.toList(), const []);
    final currentLocale = context.locale;
    final filteredLocaleEntries = useState<List<MapEntry<String, Locale>>>(localeEntries);
    final selectedLocale = useState<Locale>(currentLocale);

    final isLoading = useState<bool>(false);
    final isButtonDisabled = selectedLocale.value == currentLocale || isLoading.value;

    final searchController = useTextEditingController();
    final searchFocusNode = useFocusNode();
    final debounceTimer = useRef<Timer?>(null);

    void onSearch(String searchTerm) {
      debounceTimer.value?.cancel();
      debounceTimer.value = Timer(const Duration(milliseconds: 500), () {
        if (searchTerm.isEmpty) {
          filteredLocaleEntries.value = localeEntries;
        } else {
          filteredLocaleEntries.value =
              localeEntries.where((entry) => entry.key.toLowerCase().contains(searchTerm.toLowerCase())).toList()
                ..sort((a, b) {
                  final aKey = a.key.toLowerCase();
                  final bKey = b.key.toLowerCase();
                  final search = searchTerm.toLowerCase();

                  final aPriority = aKey.startsWith(search) ? 0 : 1;
                  final bPriority = bKey.startsWith(search) ? 0 : 1;

                  if (aPriority != bPriority) {
                    return aPriority.compareTo(bPriority);
                  }

                  return aKey.compareTo(bKey);
                });
        }
      });
    }

    void clearSearch() {
      searchController.clear();
      onSearch('');
    }

    useEffect(() {
      void searchListener() => onSearch(searchController.text);
      searchController.addListener(searchListener);
      return () {
        searchController.removeListener(searchListener);
        debounceTimer.value?.cancel();
      };
    }, [searchController]);

    return SafeArea(
      child: Column(
        children: [
          _LanguageSearchBar(
            controller: searchController,
            focusNode: searchFocusNode,
            onClear: clearSearch,
            onChanged: (_) => onSearch(searchController.text),
          ),
          Expanded(
            child: filteredLocaleEntries.value.isEmpty
                ? const _LanguageNotFound()
                : ListView.builder(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                    itemCount: filteredLocaleEntries.value.length,
                    itemExtent: 64.0,
                    scrollCacheExtent: const .pixels(100),
                    itemBuilder: (context, index) {
                      final countryName = filteredLocaleEntries.value[index].key;
                      final localeValue = filteredLocaleEntries.value[index].value;
                      final bool isSelected = selectedLocale.value == localeValue;
                      return _LanguageItem(
                        key: ValueKey(localeValue.toString()),
                        countryName: countryName,
                        localeValue: localeValue,
                        isSelected: isSelected,
                        onTap: () {
                          selectedLocale.value = localeValue;
                        },
                      );
                    },
                  ),
          ),
          if (filteredLocaleEntries.value.isNotEmpty)
            _LanguageApplyButton(
              isDisabled: isButtonDisabled,
              isLoading: isLoading.value,
              onPressed: () => _applyLanguageChange(context, selectedLocale, isLoading),
            ),
        ],
      ),
    );
  }
}

class _LanguageSearchBar extends StatelessWidget {
  const _LanguageSearchBar({
    required this.controller,
    required this.focusNode,
    required this.onClear,
    required this.onChanged,
  });

  final TextEditingController controller;
  final FocusNode focusNode;
  final VoidCallback onClear;
  final ValueChanged<String> onChanged;

  @override
  Widget build(BuildContext context) {
    final isSg = _isSgTheme(context);
    final primary = context.colorScheme.primary;
    final searchFill = isSg
        ? primary.withValues(alpha: context.isDarkTheme ? 0.22 : 0.10)
        : null;

    return Padding(
      padding: const EdgeInsets.fromLTRB(32, 16, 32, 8),
      child: isSg
          ? DecoratedBox(
              decoration: BoxDecoration(
                color: searchFill,
                borderRadius: const BorderRadius.all(Radius.circular(24)),
              ),
              child: SearchField(
                autofocus: false,
                filled: false,
                borderless: true,
                contentPadding: const EdgeInsets.all(12),
                hintText: 'language_search_hint'.t(context: context),
                prefixIcon: Icon(Icons.search_rounded, color: primary),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(icon: Icon(Icons.clear_rounded, color: primary), onPressed: onClear)
                    : null,
                controller: controller,
                onChanged: onChanged,
                focusNode: focusNode,
                onTapOutside: (_) => focusNode.unfocus(),
              ),
            )
          : DecoratedBox(
              decoration: BoxDecoration(
                borderRadius: const BorderRadius.all(Radius.circular(24)),
                gradient: LinearGradient(
                  colors: [
                    primary.withValues(alpha: 0.075),
                    primary.withValues(alpha: 0.09),
                    primary.withValues(alpha: 0.075),
                  ],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
              ),
              child: SearchField(
                autofocus: false,
                contentPadding: const EdgeInsets.all(12),
                hintText: 'language_search_hint'.t(context: context),
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: controller.text.isNotEmpty
                    ? IconButton(icon: const Icon(Icons.clear_rounded), onPressed: onClear)
                    : null,
                controller: controller,
                onChanged: onChanged,
                focusNode: focusNode,
                onTapOutside: (_) => focusNode.unfocus(),
              ),
            ),
    );
  }
}

class _LanguageNotFound extends StatelessWidget {
  const _LanguageNotFound();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_off_rounded, size: 64, color: context.colorScheme.onSurface.withValues(alpha: 0.4)),
          const SizedBox(height: 8),
          Text(
            'language_no_results_title'.t(context: context),
            style: context.textTheme.titleMedium?.copyWith(color: context.colorScheme.onSurface),
          ),
          const SizedBox(height: 4),
          Text(
            'language_no_results_subtitle'.t(context: context),
            style: context.textTheme.bodyMedium?.copyWith(color: context.colorScheme.onSurface.withValues(alpha: 0.8)),
          ),
        ],
      ),
    );
  }
}

class _LanguageApplyButton extends StatelessWidget {
  const _LanguageApplyButton({required this.isDisabled, required this.isLoading, required this.onPressed});

  final bool isDisabled;
  final bool isLoading;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16.0),
      child: SizedBox(
        width: double.infinity,
        height: 48,
        child: ElevatedButton(
          onPressed: isDisabled ? null : onPressed,
          child: isLoading
              ? const SizedBox.square(dimension: 24, child: CircularProgressIndicator(strokeWidth: 2))
              : Text(
                  'setting_languages_apply'.t(context: context),
                  style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 16.0),
                ),
        ),
      ),
    );
  }
}

class _LanguageItem extends StatelessWidget {
  const _LanguageItem({
    super.key,
    required this.countryName,
    required this.localeValue,
    required this.isSelected,
    required this.onTap,
  });

  final String countryName;
  final Locale localeValue;
  final bool isSelected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final isSg = _isSgTheme(context);
    final primary = context.colorScheme.primary;
    final onSurface = context.colorScheme.onSurface;

    final Color background;
    final Color foreground;
    final BorderSide borderSide;
    if (isSg) {
      background = isSelected
          ? primary.withValues(alpha: context.isDarkTheme ? 0.22 : 0.12)
          : (context.isDarkTheme ? sgSurfaceDark : const Color(0xFFF0F1F5));
      foreground = isSelected ? primary : onSurface;
      borderSide = isSelected
          ? BorderSide(color: context.isDarkTheme ? const Color(0xFF5D5D5D) : const Color(0xFFE7E7E7))
          : BorderSide.none;
    } else {
      background = isSelected
          ? primary.withValues(alpha: 0.15)
          : context.colorScheme.surfaceContainerLowest.withValues(alpha: .6);
      foreground = isSelected ? primary : context.colorScheme.onSurfaceVariant;
      borderSide = BorderSide(color: context.colorScheme.outlineVariant.withValues(alpha: .4), width: 1.0);
    }

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4.0),
      child: Material(
        color: background,
        shape: RoundedRectangleBorder(
          borderRadius: const BorderRadius.all(Radius.circular(16.0)),
          side: borderSide,
        ),
        clipBehavior: Clip.antiAlias,
        child: ListTile(
          title: Text(
            countryName,
            style: context.textTheme.titleSmall?.copyWith(
              fontWeight: isSelected ? FontWeight.w600 : FontWeight.w500,
              color: foreground,
            ),
          ),
          trailing: isSelected ? Icon(Icons.check, color: primary, size: 20) : null,
          onTap: onTap,
          selected: isSelected,
          selectedTileColor: Colors.transparent,
          shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(16.0))),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16.0),
        ),
      ),
    );
  }
}
