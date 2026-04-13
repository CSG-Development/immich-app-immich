import 'package:immich_mobile/domain/models/advanced_exif.model.dart';
import 'package:immich_mobile/domain/models/exif.model.dart';

class AdvancedExifMapper {
  const AdvancedExifMapper._();

  static AdvancedExifInfo fromBackendExif(ExifInfo? exifInfo) {
    if (exifInfo == null) {
      return AdvancedExifInfo.empty;
    }

    final imageItems = <AdvancedExifItem?>[
      _stringItem('advanced_exif_image_width', _toWholeNumber(exifInfo.width)),
      _stringItem('advanced_exif_image_height', _toWholeNumber(exifInfo.height)),
      _stringItem('advanced_exif_orientation', exifInfo.orientation),
    ].whereType<AdvancedExifItem>().toList();

    final cameraItems = <AdvancedExifItem?>[
      _stringItem('advanced_exif_camera_make', exifInfo.make),
      _stringItem('advanced_exif_camera_model', exifInfo.model),
      _stringItem('advanced_exif_camera_lens', exifInfo.lens),
      _stringItem('advanced_exif_camera_fnumber', _fixed(exifInfo.f)),
      _stringItem('advanced_exif_camera_focal_length', _fixed(exifInfo.mm)),
      _stringItem('advanced_exif_camera_iso', exifInfo.iso?.toString()),
      _stringItem('advanced_exif_camera_exposure_seconds', _fixed(exifInfo.exposureSeconds)),
      _stringItem('advanced_exif_camera_exposure_display', exifInfo.exposureTime),
    ].whereType<AdvancedExifItem>().toList();

    final locationItems = <AdvancedExifItem?>[
      _stringItem('advanced_exif_location_latitude', _fixed(exifInfo.latitude)),
      _stringItem('advanced_exif_location_longitude', _fixed(exifInfo.longitude)),
      _stringItem('advanced_exif_location_city', exifInfo.city),
      _stringItem('advanced_exif_location_state', exifInfo.state),
      _stringItem('advanced_exif_location_country', exifInfo.country),
    ].whereType<AdvancedExifItem>().toList();

    final fileItems = <AdvancedExifItem?>[
      _stringItem('advanced_exif_file_size_bytes', exifInfo.fileSize?.toString()),
      _stringItem('advanced_exif_file_timezone', exifInfo.timeZone),
      _stringItem('advanced_exif_file_datetime_original', exifInfo.dateTimeOriginal?.toIso8601String()),
      _stringItem('advanced_exif_file_modify_date', exifInfo.modifyDate?.toIso8601String()),
      _stringItem('advanced_exif_file_description', exifInfo.description),
      _stringItem('advanced_exif_file_projection_type', exifInfo.projectionType),
      _stringItem('advanced_exif_file_rating', exifInfo.rating?.toString()),
    ].whereType<AdvancedExifItem>().toList();

    final sections = <AdvancedExifSection>[
      if (imageItems.isNotEmpty) AdvancedExifSection(key: 'advanced_exif_section_image', items: imageItems),
      if (cameraItems.isNotEmpty) AdvancedExifSection(key: 'advanced_exif_section_camera', items: cameraItems),
      if (locationItems.isNotEmpty)
        AdvancedExifSection(key: 'advanced_exif_section_location', items: locationItems),
      if (fileItems.isNotEmpty) AdvancedExifSection(key: 'advanced_exif_section_file', items: fileItems),
    ];

    return AdvancedExifInfo(sections: sections);
  }

  static AdvancedExifItem? _stringItem(String key, String? value) {
    if (value == null || value.trim().isEmpty) {
      return null;
    }
    return AdvancedExifItem(
      key: key,
      value: value.trim(),
      source: AdvancedExifValueSource.backend,
    );
  }

  static String? _fixed(double? value) {
    if (value == null) {
      return null;
    }
    if (value == value.toInt()) {
      return value.toInt().toString();
    }
    return value.toStringAsFixed(4).replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '');
  }

  static String? _toWholeNumber(double? value) {
    if (value == null) {
      return null;
    }
    return value.toInt().toString();
  }
}
