class AdvancedExifSection {
  final String key;
  final List<AdvancedExifItem> items;

  const AdvancedExifSection({required this.key, required this.items});

  bool get hasItems => items.isNotEmpty;
}

class AdvancedExifItem {
  final String key;
  final String value;
  final AdvancedExifValueSource source;

  const AdvancedExifItem({
    required this.key,
    required this.value,
    required this.source,
  });
}

enum AdvancedExifValueSource { backend, local }

class AdvancedExifInfo {
  final List<AdvancedExifSection> sections;

  const AdvancedExifInfo({required this.sections});

  static const AdvancedExifInfo empty = AdvancedExifInfo(sections: []);

  bool get hasData => sections.any((section) => section.hasItems);

  static AdvancedExifInfo mergeBackendFirst({
    required AdvancedExifInfo? backend,
    required AdvancedExifInfo? local,
  }) {
    final backendMap = _toMap(backend);
    final localMap = _toMap(local);
    final sectionOrder = <String>[
      ...backendMap.keys,
      ...localMap.keys.where((key) => !backendMap.containsKey(key)),
    ];

    final sections = <AdvancedExifSection>[];
    for (final sectionKey in sectionOrder) {
      final backendItems = backendMap[sectionKey] ?? const <String, AdvancedExifItem>{};
      final localItems = localMap[sectionKey] ?? const <String, AdvancedExifItem>{};

      final itemOrder = <String>[
        ...backendItems.keys,
        ...localItems.keys.where((key) => !backendItems.containsKey(key)),
      ];

      final mergedItems = <AdvancedExifItem>[];
      for (final itemKey in itemOrder) {
        final backendItem = backendItems[itemKey];
        final localItem = localItems[itemKey];
        final chosen = backendItem ?? localItem;
        if (chosen == null) {
          continue;
        }
        if (chosen.value.trim().isEmpty) {
          continue;
        }
        mergedItems.add(chosen);
      }

      if (mergedItems.isNotEmpty) {
        sections.add(AdvancedExifSection(key: sectionKey, items: mergedItems));
      }
    }

    return AdvancedExifInfo(sections: sections);
  }

  static Map<String, Map<String, AdvancedExifItem>> _toMap(AdvancedExifInfo? info) {
    final result = <String, Map<String, AdvancedExifItem>>{};
    if (info == null) {
      return result;
    }

    for (final section in info.sections) {
      final sectionItems = <String, AdvancedExifItem>{};
      for (final item in section.items) {
        sectionItems[item.key] = item;
      }
      result[section.key] = sectionItems;
    }

    return result;
  }
}
