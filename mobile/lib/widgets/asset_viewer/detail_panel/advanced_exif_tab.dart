import 'package:flutter/material.dart';
import 'package:immich_mobile/domain/models/advanced_exif.model.dart';
import 'package:immich_mobile/extensions/build_context_extensions.dart';
import 'package:immich_mobile/extensions/translate_extensions.dart';

class AdvancedExifTab extends StatefulWidget {
  final AdvancedExifInfo info;

  const AdvancedExifTab({super.key, required this.info});

  @override
  State<AdvancedExifTab> createState() => _AdvancedExifTabState();
}

class _AdvancedExifTabState extends State<AdvancedExifTab> {
  late final Set<String> _expandedSectionTitles;
  bool _showEmptyTags = false;

  @override
  void initState() {
    super.initState();
    _expandedSectionTitles = <String>{
      if (_templateSections.isNotEmpty) _templateSections.first.$1,
    };
  }

  @override
  Widget build(BuildContext context) {
    final itemMap = <String, AdvancedExifItem>{};
    for (final section in widget.info.sections) {
      for (final item in section.items) {
        itemMap[item.key] = item;
      }
    }
    final knownKeys = _templateSections.expand((s) => s.$2).toSet();
    final extraItems = widget.info.sections
        .expand((section) => section.items)
        .where((item) => !knownKeys.contains(item.key))
        .toList();

    final hasExtraSection = extraItems.isNotEmpty;
    final allSectionTitles = <String>[
      ..._templateSections.map((s) => s.$1),
      if (hasExtraSection) _additionalSectionTitle,
    ];
    final bool allExpanded = _expandedSectionTitles.containsAll(allSectionTitles);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisAlignment: MainAxisAlignment.end,
          children: [
            TextButton.icon(
              onPressed: () {
                setState(() {
                  _showEmptyTags = !_showEmptyTags;
                });
              },
              icon: Icon(_showEmptyTags ? Icons.visibility_off : Icons.visibility),
              label: Text(
                _showEmptyTags
                    ? _trOrFallback(context, 'advanced_exif_hide_empty_tags', 'Hide empty tags')
                    : _trOrFallback(context, 'advanced_exif_show_all_tags', 'Show all tags'),
              ),
            ),
            TextButton.icon(
              onPressed: () {
                setState(() {
                  if (allExpanded) {
                    _expandedSectionTitles
                      ..clear()
                      ..add(_templateSections.first.$1);
                  } else {
                    _expandedSectionTitles
                      ..clear()
                      ..addAll(allSectionTitles);
                  }
                });
              },
              icon: Icon(allExpanded ? Icons.unfold_less : Icons.unfold_more),
              label: Text(
                allExpanded
                    ? _trOrFallback(context, 'collapse_all', 'Collapse all')
                    : _trOrFallback(context, 'expand_all', 'Expand all'),
              ),
            ),
          ],
        ),
        for (final section in _templateSections) ...[
          ...() {
            final allItems =
                section.$2.map((itemKey) => itemMap[itemKey] ?? _placeholder(itemKey)).toList();
            final visibleItems =
                _showEmptyTags ? allItems : allItems.where((item) => item.value != '-').toList();
            if (visibleItems.isEmpty) {
              return const <Widget>[];
            }
            return <Widget>[
          _AdvancedSection(
            sectionTitle: _trOrFallback(context, section.$1, _sectionTitleFallback(section.$1)),
            isExpanded: _expandedSectionTitles.contains(section.$1),
            onToggle: () {
              setState(() {
                if (_expandedSectionTitles.contains(section.$1)) {
                  _expandedSectionTitles.remove(section.$1);
                } else {
                  _expandedSectionTitles.add(section.$1);
                }
              });
            },
            items: visibleItems,
          ),
              const SizedBox(height: 8),
            ];
          }(),
        ],
        ...() {
          final visibleExtras =
              _showEmptyTags ? extraItems : extraItems.where((item) => item.value != '-').toList();
          if (visibleExtras.isEmpty) {
            return const <Widget>[];
          }
          return <Widget>[
            _AdvancedSection(
              sectionTitle: _trOrFallback(
                context,
                _additionalSectionTitle,
                'Additional Tags',
              ),
              isExpanded: _expandedSectionTitles.contains(_additionalSectionTitle),
              onToggle: () {
                setState(() {
                  if (_expandedSectionTitles.contains(_additionalSectionTitle)) {
                    _expandedSectionTitles.remove(_additionalSectionTitle);
                  } else {
                    _expandedSectionTitles.add(_additionalSectionTitle);
                  }
                });
              },
              items: visibleExtras,
            ),
            const SizedBox(height: 8),
          ];
        }(),
      ],
    );
  }

  AdvancedExifItem _placeholder(String key) {
    return const AdvancedExifItem(
      key: '',
      value: '-',
      source: AdvancedExifValueSource.backend,
    ).copyWithKey(key);
  }
}

class _AdvancedSection extends StatelessWidget {
  final String sectionTitle;
  final List<AdvancedExifItem> items;
  final bool isExpanded;
  final VoidCallback onToggle;

  const _AdvancedSection({
    required this.sectionTitle,
    required this.items,
    required this.isExpanded,
    required this.onToggle,
  });

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 0,
      margin: EdgeInsets.zero,
      color: context.colorScheme.surfaceContainer,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.all(Radius.circular(16)),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
        child: Column(
          children: [
            InkWell(
              onTap: onToggle,
              borderRadius: const BorderRadius.all(Radius.circular(12)),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        sectionTitle,
                        style: context.textTheme.labelMedium?.copyWith(
                          color: context.colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    Icon(
                      isExpanded ? Icons.expand_less : Icons.expand_more,
                      color: context.colorScheme.onSurfaceVariant,
                    ),
                  ],
                ),
              ),
            ),
            if (isExpanded)
              Padding(
                padding: const EdgeInsets.fromLTRB(8, 0, 8, 8),
                child: Column(
                  children: [for (final item in items) _AdvancedRow(item: item)],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

String _humanizeLabel(String key) {
  final words = key.split('_').where((e) => e.isNotEmpty);
  return words.map((word) => '${word[0].toUpperCase()}${word.substring(1)}').join(' ');
}

class _AdvancedRow extends StatelessWidget {
  final AdvancedExifItem item;

  const _AdvancedRow({required this.item});

  @override
  Widget build(BuildContext context) {
    final label = item.key.startsWith('advanced_exif_dynamic_')
        ? _humanize(item.key.replaceFirst('advanced_exif_dynamic_', ''))
        : _label(context, item.key);

    final hasValue = item.value != '-';
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 2,
            child: Text(
              label,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 3,
            child: SelectableText(
              item.value,
              style: context.textTheme.bodySmall?.copyWith(
                color: context.colorScheme.onSurface,
              ),
            ),
          ),
          const SizedBox(width: 8),
          if (hasValue)
            Text(
              item.source == AdvancedExifValueSource.backend ? 'BE' : 'LOCAL',
              style: context.textTheme.labelSmall?.copyWith(
                color: context.colorScheme.primary,
                fontWeight: FontWeight.w600,
              ),
            ),
        ],
      ),
    );
  }

  String _humanize(String key) {
    return _humanizeLabel(key);
  }

  String _label(BuildContext context, String key) {
    final fallback = switch (key) {
      'advanced_exif_image_width' => 'Width',
      'advanced_exif_image_height' => 'Height',
      'advanced_exif_image_type' => 'Type',
      'advanced_exif_image_mime_type' => 'MIME Type',
      'advanced_exif_image_color_space' => 'Color Space',
      'advanced_exif_image_bits_per_sample' => 'Bits Per Sample',
      'advanced_exif_orientation' => 'Orientation',
      'advanced_exif_date_time' => 'Date Time',
      'advanced_exif_create_date' => 'Create Date',
      'advanced_exif_timezone_offset' => 'Time Zone Offset',
      'advanced_exif_camera_make' => 'Make',
      'advanced_exif_camera_model' => 'Model',
      'advanced_exif_camera_body_serial_number' => 'Body Serial Number',
      'advanced_exif_camera_temperature' => 'Camera Temperature',
      'advanced_exif_camera_exposure_mode' => 'Exposure Mode',
      'advanced_exif_camera_lens' => 'Lens',
      'advanced_exif_lens_id' => 'Lens ID',
      'advanced_exif_lens_serial_number' => 'Lens Serial Number',
      'advanced_exif_camera_fnumber' => 'F-Number',
      'advanced_exif_camera_focal_length' => 'Focal Length',
      'advanced_exif_focal_length_35mm' => 'Focal Length (35mm)',
      'advanced_exif_aperture' => 'Aperture',
      'advanced_exif_max_aperture' => 'Max Aperture',
      'advanced_exif_camera_iso' => 'ISO',
      'advanced_exif_exposure_time' => 'Exposure Time',
      'advanced_exif_camera_exposure_seconds' => 'Exposure (Seconds)',
      'advanced_exif_camera_exposure_display' => 'Exposure',
      'advanced_exif_shutter_speed' => 'Shutter Speed',
      'advanced_exif_exposure_compensation' => 'Exposure Compensation',
      'advanced_exif_metering_mode' => 'Metering Mode',
      'advanced_exif_white_balance' => 'White Balance',
      'advanced_exif_flash' => 'Flash',
      'advanced_exif_brightness' => 'Brightness',
      'advanced_exif_contrast' => 'Contrast',
      'advanced_exif_saturation' => 'Saturation',
      'advanced_exif_sharpness' => 'Sharpness',
      'advanced_exif_scene_capture_type' => 'Scene Capture Type',
      'advanced_exif_digital_zoom_ratio' => 'Digital Zoom Ratio',
      'advanced_exif_location_latitude' => 'Latitude',
      'advanced_exif_location_longitude' => 'Longitude',
      'advanced_exif_location_altitude' => 'Altitude',
      'advanced_exif_location_speed' => 'Speed',
      'advanced_exif_location_img_direction' => 'Image Direction',
      'advanced_exif_location_dest_bearing' => 'Destination Bearing',
      'advanced_exif_location_city' => 'City',
      'advanced_exif_location_state' => 'State',
      'advanced_exif_location_country' => 'Country',
      'advanced_exif_location_latitude_ref' => 'Latitude Ref',
      'advanced_exif_location_longitude_ref' => 'Longitude Ref',
      'advanced_exif_location_altitude_ref' => 'Altitude Ref',
      'advanced_exif_location_date_stamp' => 'GPS Date Stamp',
      'advanced_exif_location_time_stamp' => 'GPS Time Stamp',
      'advanced_exif_location_processing_method' => 'GPS Processing Method',
      'advanced_exif_location_map_datum' => 'GPS Map Datum',
      'advanced_exif_location_h_positioning_error' => 'GPS H Positioning Error',
      'advanced_exif_file_name' => 'File Name',
      'advanced_exif_file_type' => 'File Type',
      'advanced_exif_file_type_extension' => 'File Type Extension',
      'advanced_exif_file_directory' => 'Directory',
      'advanced_exif_file_size_bytes' => 'File Size (bytes)',
      'advanced_exif_file_timezone' => 'Time Zone',
      'advanced_exif_file_datetime_original' => 'Date Time Original',
      'advanced_exif_file_modify_date' => 'Modify Date',
      'advanced_exif_file_description' => 'Description',
      'advanced_exif_file_projection_type' => 'Projection Type',
      'advanced_exif_file_rating' => 'Rating',
      'advanced_exif_subject_distance' => 'Subject Distance',
      'advanced_exif_noise_reduction' => 'Noise Reduction',
      'advanced_exif_exposure_program' => 'Exposure Program',
      'advanced_exif_sensitivity_type' => 'Sensitivity Type',
      'advanced_exif_recommended_exposure_index' => 'Recommended Exposure Index',
      'advanced_exif_light_source' => 'Light Source',
      'advanced_exif_custom_rendered' => 'Custom Rendered',
      'advanced_exif_gain_control' => 'Gain Control',
      'advanced_exif_subject_distance_range' => 'Subject Distance Range',
      'advanced_exif_scene_type' => 'Scene Type',
      'advanced_exif_sensing_method' => 'Sensing Method',
      'advanced_exif_file_source' => 'File Source',
      'advanced_exif_software' => 'Software',
      'advanced_exif_file_artist' => 'Artist',
      'advanced_exif_file_copyright' => 'Copyright',
      'advanced_exif_file_host_computer' => 'Host Computer',
      'advanced_exif_thumbnail_offset' => 'Thumbnail Offset',
      'advanced_exif_thumbnail_length' => 'Thumbnail Length',
      'advanced_exif_thumbnail_image' => 'Thumbnail',
      _ => _humanize(key),
    };
    final translationKey = _labelTranslationKey(key);
    if (translationKey == null) {
      return fallback;
    }
    return _trOrFallback(context, translationKey, fallback);
  }
}

const List<(String, List<String>)> _templateSections = [
  (
    'metadata_info.image_information',
    [
      'advanced_exif_image_width',
      'advanced_exif_image_height',
      'advanced_exif_image_type',
      'advanced_exif_image_mime_type',
      'advanced_exif_image_color_space',
      'advanced_exif_image_bits_per_sample',
      'advanced_exif_orientation',
    ],
  ),
  (
    'metadata_info.date_and_time',
    [
      'advanced_exif_file_datetime_original',
      'advanced_exif_date_time',
      'advanced_exif_create_date',
      'advanced_exif_file_modify_date',
      'advanced_exif_timezone_offset',
      'advanced_exif_file_timezone',
    ],
  ),
  (
    'metadata_info.camera_settings',
    [
      'advanced_exif_camera_make',
      'advanced_exif_camera_model',
      'advanced_exif_camera_body_serial_number',
      'advanced_exif_camera_temperature',
      'advanced_exif_camera_exposure_mode',
      'advanced_exif_camera_iso',
      'advanced_exif_exposure_time',
      'advanced_exif_shutter_speed',
    ],
  ),
  (
    'metadata_info.lens_and_focal_length',
    [
      'advanced_exif_camera_lens',
      'advanced_exif_lens_id',
      'advanced_exif_lens_serial_number',
      'advanced_exif_camera_focal_length',
      'advanced_exif_focal_length_35mm',
      'advanced_exif_camera_fnumber',
      'advanced_exif_aperture',
      'advanced_exif_max_aperture',
    ],
  ),
  (
    'metadata_info.image_processing',
    [
      'advanced_exif_exposure_compensation',
      'advanced_exif_metering_mode',
      'advanced_exif_white_balance',
      'advanced_exif_flash',
      'advanced_exif_brightness',
      'advanced_exif_contrast',
      'advanced_exif_saturation',
      'advanced_exif_sharpness',
      'advanced_exif_scene_capture_type',
      'advanced_exif_digital_zoom_ratio',
      'advanced_exif_noise_reduction',
      'advanced_exif_exposure_program',
      'advanced_exif_sensitivity_type',
      'advanced_exif_recommended_exposure_index',
      'advanced_exif_light_source',
      'advanced_exif_custom_rendered',
      'advanced_exif_gain_control',
      'advanced_exif_subject_distance_range',
      'advanced_exif_scene_type',
      'advanced_exif_sensing_method',
      'advanced_exif_file_source',
    ],
  ),
  (
    'metadata_info.gps_data',
    [
      'advanced_exif_location_latitude',
      'advanced_exif_location_longitude',
      'advanced_exif_location_altitude',
      'advanced_exif_location_speed',
      'advanced_exif_location_img_direction',
      'advanced_exif_location_dest_bearing',
      'advanced_exif_location_city',
      'advanced_exif_location_state',
      'advanced_exif_location_country',
      'advanced_exif_location_latitude_ref',
      'advanced_exif_location_longitude_ref',
      'advanced_exif_location_altitude_ref',
      'advanced_exif_location_date_stamp',
      'advanced_exif_location_time_stamp',
      'advanced_exif_location_processing_method',
      'advanced_exif_location_map_datum',
      'advanced_exif_location_h_positioning_error',
    ],
  ),
  (
    'metadata_info.file_information',
    [
      'advanced_exif_file_name',
      'advanced_exif_file_size_bytes',
      'advanced_exif_file_type',
      'advanced_exif_file_type_extension',
      'advanced_exif_file_directory',
      'advanced_exif_software',
      'advanced_exif_file_description',
      'advanced_exif_file_artist',
      'advanced_exif_file_copyright',
      'advanced_exif_file_host_computer',
    ],
  ),
  (
    'metadata_info.advanced_settings',
    [
      'advanced_exif_file_projection_type',
      'advanced_exif_file_rating',
      'advanced_exif_subject_distance',
      'advanced_exif_camera_exposure_seconds',
      'advanced_exif_camera_exposure_display',
    ],
  ),
  (
    'metadata_info.thumbnail',
    [
      'advanced_exif_thumbnail_offset',
      'advanced_exif_thumbnail_length',
      'advanced_exif_thumbnail_image',
    ],
  ),
];

const String _additionalSectionTitle = 'advanced_exif_additional_tags';

String _sectionTitleFallback(String key) {
  return switch (key) {
    'metadata_info.image_information' => 'Image Information',
    'metadata_info.date_and_time' => 'Date & Time',
    'metadata_info.camera_settings' => 'Camera Settings',
    'metadata_info.lens_and_focal_length' => 'Lens & Focal Length',
    'metadata_info.image_processing' => 'Image Processing',
    'metadata_info.gps_data' => 'GPS Data',
    'metadata_info.file_information' => 'File Information',
    'metadata_info.advanced_settings' => 'Advanced Settings',
    'metadata_info.thumbnail' => 'Thumbnail',
    _ => key,
  };
}

String? _labelTranslationKey(String key) {
  return switch (key) {
    'advanced_exif_image_width' => 'metadata_info.image_width',
    'advanced_exif_image_height' => 'metadata_info.image_height',
    'advanced_exif_image_color_space' => 'metadata_info.color_space',
    'advanced_exif_image_bits_per_sample' => 'metadata_info.bits_per_sample',
    'advanced_exif_orientation' => 'metadata_info.orientation',
    'advanced_exif_date_time' => 'metadata_info.date_time',
    'advanced_exif_camera_make' => 'metadata_info.make',
    'advanced_exif_camera_model' => 'metadata_info.model',
    'advanced_exif_camera_exposure_mode' => 'metadata_info.exposure_mode',
    'advanced_exif_camera_lens' => 'metadata_info.lens_model',
    'advanced_exif_lens_serial_number' => 'metadata_info.lens_serial_number',
    'advanced_exif_camera_fnumber' => 'metadata_info.f_number',
    'advanced_exif_camera_focal_length' => 'metadata_info.focal_length',
    'advanced_exif_focal_length_35mm' => 'metadata_info.focal_length_in_35mm_film',
    'advanced_exif_aperture' => 'metadata_info.aperture_value',
    'advanced_exif_max_aperture' => 'metadata_info.max_aperture_value',
    'advanced_exif_camera_iso' => 'metadata_info.iso_speed_ratings',
    'advanced_exif_exposure_time' => 'metadata_info.exposure_time',
    'advanced_exif_shutter_speed' => 'metadata_info.shutter_speed_value',
    'advanced_exif_exposure_compensation' => 'metadata_info.exposure_bias_value',
    'advanced_exif_metering_mode' => 'metadata_info.metering_mode',
    'advanced_exif_white_balance' => 'metadata_info.white_balance',
    'advanced_exif_flash' => 'metadata_info.flash',
    'advanced_exif_brightness' => 'metadata_info.brightness_value',
    'advanced_exif_contrast' => 'metadata_info.contrast',
    'advanced_exif_saturation' => 'metadata_info.saturation',
    'advanced_exif_sharpness' => 'metadata_info.sharpness',
    'advanced_exif_scene_capture_type' => 'metadata_info.scene_capture_type',
    'advanced_exif_digital_zoom_ratio' => 'metadata_info.digital_zoom_ratio',
    'advanced_exif_location_latitude' => 'metadata_info.gps_latitude',
    'advanced_exif_location_longitude' => 'metadata_info.gps_longitude',
    'advanced_exif_location_altitude' => 'metadata_info.gps_altitude',
    'advanced_exif_location_latitude_ref' => 'metadata_info.gps_latitude_ref',
    'advanced_exif_location_longitude_ref' => 'metadata_info.gps_longitude_ref',
    'advanced_exif_location_altitude_ref' => 'metadata_info.gps_altitude_ref',
    'advanced_exif_location_date_stamp' => 'metadata_info.gps_date_stamp',
    'advanced_exif_location_time_stamp' => 'metadata_info.gps_time_stamp',
    'advanced_exif_file_datetime_original' => 'metadata_info.date_time_original',
    'advanced_exif_file_modify_date' => 'metadata_info.modify_date',
    'advanced_exif_file_description' => 'metadata_info.image_description',
    'advanced_exif_file_projection_type' => 'metadata_info.projection_type',
    'advanced_exif_file_rating' => 'metadata_info.rating',
    'advanced_exif_exposure_program' => 'metadata_info.exposure_program',
    'advanced_exif_sensitivity_type' => 'metadata_info.sensitivity_type',
    'advanced_exif_recommended_exposure_index' => 'metadata_info.exposure_index',
    'advanced_exif_light_source' => 'metadata_info.light_source',
    'advanced_exif_custom_rendered' => 'metadata_info.custom_rendered',
    'advanced_exif_gain_control' => 'metadata_info.gain_control',
    'advanced_exif_scene_type' => 'metadata_info.scene_type',
    'advanced_exif_sensing_method' => 'metadata_info.sensing_method',
    'advanced_exif_file_source' => 'metadata_info.file_source',
    'advanced_exif_software' => 'metadata_info.software',
    'advanced_exif_file_artist' => 'metadata_info.artist',
    'advanced_exif_file_copyright' => 'metadata_info.copyright',
    _ => null,
  };
}

String _trOrFallback(BuildContext context, String key, String fallback) {
  final translated = key.t(context: context);
  return translated == key ? fallback : translated;
}

extension on AdvancedExifItem {
  AdvancedExifItem copyWithKey(String key) =>
      AdvancedExifItem(key: key, value: value, source: source);
}
