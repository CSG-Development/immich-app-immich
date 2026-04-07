import 'package:flutter/material.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';
import 'package:immich_mobile/models/search/search_filter.model.dart';

class ExifPicker extends StatefulWidget {
  const ExifPicker({
    super.key,
    required this.onSelect,
    this.filter = const [],
  });

  final ValueChanged<List<SearchExifFilterPair>> onSelect;
  final List<SearchExifFilterPair> filter;

  @override
  State<ExifPicker> createState() => _ExifPickerState();
}

class _ExifPickerState extends State<ExifPicker> {
  late final List<SearchExifFilterPair> _rows;

  @override
  void initState() {
    super.initState();
    _rows = widget.filter.isEmpty
        ? [SearchExifFilterPair()]
        : widget.filter.map((pair) => SearchExifFilterPair(tag: pair.tag, value: pair.value)).toList();
  }

  void _notify() {
    widget.onSelect(_rows.map((pair) => SearchExifFilterPair(tag: pair.tag, value: pair.value)).toList());
  }

  void _addRow() {
    setState(() {
      _rows.add(SearchExifFilterPair());
    });
    _notify();
  }

  void _removeRow(int index) {
    if (_rows.length == 1) {
      setState(() {
        _rows[0] = SearchExifFilterPair();
      });
      _notify();
      return;
    }
    setState(() {
      _rows.removeAt(index);
    });
    _notify();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compactLayout = constraints.maxWidth < 720;

        return Column(
          mainAxisSize: MainAxisSize.max,
          children: [
            Expanded(
              child: ListView.separated(
                shrinkWrap: true,
                keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                itemCount: _rows.length,
                separatorBuilder: (_, __) => const SizedBox(height: 8),
                itemBuilder: (context, index) {
                  final row = _rows[index];
                  return DecoratedBox(
                    key: ObjectKey(row),
                    decoration: BoxDecoration(
                      color: context.colorScheme.surfaceContainerLow,
                      borderRadius: const BorderRadius.all(Radius.circular(16)),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 8, 10),
                      child: compactLayout
                          ? Column(
                              children: [
                                DropdownButtonFormField<String>(
                                  value: row.tag,
                                  isExpanded: true,
                                  decoration: InputDecoration(
                                    labelText: _trOrFallback(context, 'search_filter_exif_tag', 'EXIF tag'),
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: context.colorScheme.surface,
                                  ),
                                  items: _exifTagOptions
                                      .map(
                                        (option) => DropdownMenuItem<String>(
                                          value: option.tag,
                                          child: Text(_trOrFallback(context, option.labelKey, option.fallback)),
                                        ),
                                      )
                                      .toList(),
                                  onChanged: (value) {
                                    setState(() {
                                      row.tag = value;
                                    });
                                    _notify();
                                  },
                                ),
                                const SizedBox(height: 8),
                                TextFormField(
                                  initialValue: row.value,
                                  decoration: InputDecoration(
                                    labelText: _trOrFallback(context, 'search_filter_exif_value', 'Value'),
                                    border: const OutlineInputBorder(),
                                    filled: true,
                                    fillColor: context.colorScheme.surface,
                                  ),
                                  onChanged: (value) {
                                    row.value = value;
                                    _notify();
                                  },
                                ),
                                Align(
                                  alignment: Alignment.centerRight,
                                  child: IconButton(
                                    tooltip: 'delete'.t(context: context),
                                    icon: const Icon(Icons.remove_circle_outline),
                                    onPressed: () => _removeRow(index),
                                  ),
                                ),
                              ],
                            )
                          : Row(
                              children: [
                                Expanded(
                                  flex: 4,
                                  child: DropdownButtonFormField<String>(
                                    value: row.tag,
                                    isExpanded: true,
                                    decoration: InputDecoration(
                                      labelText: _trOrFallback(context, 'search_filter_exif_tag', 'EXIF tag'),
                                      border: const OutlineInputBorder(),
                                      filled: true,
                                      fillColor: context.colorScheme.surface,
                                    ),
                                    items: _exifTagOptions
                                        .map(
                                          (option) => DropdownMenuItem<String>(
                                            value: option.tag,
                                            child: Text(_trOrFallback(context, option.labelKey, option.fallback)),
                                          ),
                                        )
                                        .toList(),
                                    onChanged: (value) {
                                      setState(() {
                                        row.tag = value;
                                      });
                                      _notify();
                                    },
                                  ),
                                ),
                                const SizedBox(width: 8),
                                Expanded(
                                  flex: 5,
                                  child: TextFormField(
                                    initialValue: row.value,
                                    decoration: InputDecoration(
                                      labelText: _trOrFallback(context, 'search_filter_exif_value', 'Value'),
                                      border: const OutlineInputBorder(),
                                      filled: true,
                                      fillColor: context.colorScheme.surface,
                                    ),
                                    onChanged: (value) {
                                      row.value = value;
                                      _notify();
                                    },
                                  ),
                                ),
                                IconButton(
                                  tooltip: 'delete'.t(context: context),
                                  icon: const Icon(Icons.remove_circle_outline),
                                  onPressed: () => _removeRow(index),
                                ),
                              ],
                            ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 8),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _addRow,
                icon: const Icon(Icons.add),
                label: Text(_trOrFallback(context, 'search_filter_exif_add_new', 'Add new')),
              ),
            ),
          ],
        );
      },
    );
  }
}

class _ExifTagOption {
  final String tag;
  final String labelKey;
  final String fallback;

  const _ExifTagOption({required this.tag, required this.labelKey, required this.fallback});
}

const List<_ExifTagOption> _exifTagOptions = [
  _ExifTagOption(tag: 'make', labelKey: 'metadata_info.make', fallback: 'Make'),
  _ExifTagOption(tag: 'model', labelKey: 'metadata_info.model', fallback: 'Model'),
  _ExifTagOption(tag: 'lensModel', labelKey: 'metadata_info.lens_model', fallback: 'Lens model'),
  _ExifTagOption(tag: 'focalLength', labelKey: 'metadata_info.focal_length', fallback: 'Focal length'),
  _ExifTagOption(tag: 'fNumber', labelKey: 'metadata_info.f_number', fallback: 'F number'),
  _ExifTagOption(tag: 'iso', labelKey: 'metadata_info.iso_speed_ratings', fallback: 'ISO speed ratings'),
  _ExifTagOption(tag: 'exposureTime', labelKey: 'metadata_info.exposure_time', fallback: 'Exposure time'),
  _ExifTagOption(tag: 'flash', labelKey: 'metadata_info.flash', fallback: 'Flash'),
  _ExifTagOption(tag: 'whiteBalance', labelKey: 'metadata_info.white_balance', fallback: 'White balance'),
  _ExifTagOption(tag: 'city', labelKey: 'city', fallback: 'City'),
  _ExifTagOption(tag: 'state', labelKey: 'state', fallback: 'State'),
  _ExifTagOption(tag: 'country', labelKey: 'country', fallback: 'Country'),
  _ExifTagOption(tag: 'description', labelKey: 'metadata_info.image_description', fallback: 'Image description'),
  _ExifTagOption(tag: 'software', labelKey: 'metadata_info.software', fallback: 'Software'),
  _ExifTagOption(tag: 'orientation', labelKey: 'metadata_info.orientation', fallback: 'Orientation'),
];

String _trOrFallback(BuildContext context, String key, String fallback) {
  final translated = key.t(context: context);
  return translated == key ? fallback : translated;
}
