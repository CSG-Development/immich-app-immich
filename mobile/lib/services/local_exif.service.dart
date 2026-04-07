import 'dart:io';

import 'package:exif/exif.dart';
import 'package:immich_mobile/domain/models/advanced_exif.model.dart';
import 'package:immich_mobile/domain/models/asset/base_asset.model.dart';
import 'package:immich_mobile/entities/asset.entity.dart';
import 'package:logging/logging.dart';
import 'package:photo_manager/photo_manager.dart';

class LocalExifService {
  final Logger _log = Logger('LocalExifService');

  Future<AdvancedExifInfo> getAdvancedExif(Asset asset) async {
    if (!asset.isLocal || asset.local == null) {
      return AdvancedExifInfo.empty;
    }

    try {
      final File? file = await asset.local!.file;
      if (file == null || !file.existsSync()) {
        return AdvancedExifInfo.empty;
      }
      final parsed = await _readExifFromFile(file, label: asset.fileName);
      if (parsed.hasData) {
        return parsed;
      }
      return await _fallbackFromLegacyAsset(asset, file);
    } catch (error, stackTrace) {
      _log.warning('Failed to parse local EXIF for ${asset.fileName}', error, stackTrace);
      return AdvancedExifInfo.empty;
    }
  }

  /// Beta timeline / drift: [BaseAsset] with a gallery [localId] (LocalAsset.id or RemoteAsset.localId).
  Future<AdvancedExifInfo> getAdvancedExifFromBaseAsset(BaseAsset asset) async {
    final String? localId = switch (asset) {
      LocalAsset l => l.id,
      RemoteAsset r => r.localId,
    };
    if (localId == null) {
      return AdvancedExifInfo.empty;
    }

    try {
      final entity = await AssetEntity.fromId(localId);
      if (entity == null) {
        return AdvancedExifInfo.empty;
      }

      final File? file = await entity.originFile ?? await entity.file;
      if (file == null || !file.existsSync()) {
        return AdvancedExifInfo.empty;
      }
      final parsed = await _readExifFromFile(file, label: asset.name);
      if (parsed.hasData) {
        return parsed;
      }
      return await _fallbackFromBaseAsset(asset, entity, file);
    } catch (error, stackTrace) {
      _log.warning('Failed to parse local EXIF for BaseAsset ${asset.name}', error, stackTrace);
      return AdvancedExifInfo.empty;
    }
  }

  Future<AdvancedExifInfo> _readExifFromFile(File file, {required String label}) async {
    try {
      final bytes = await file.readAsBytes();
      final tags = await readExifFromBytes(bytes);
      if (tags.isEmpty) {
        return AdvancedExifInfo.empty;
      }
      return _mapTags(tags);
    } catch (error, stackTrace) {
      _log.warning('Failed to read EXIF from file for $label', error, stackTrace);
      return AdvancedExifInfo.empty;
    }
  }

  AdvancedExifInfo _mapTags(Map<String, IfdTag> tags) {
    final grouped = <String, List<AdvancedExifItem>>{};

    void put(String sectionKey, String key, String value) {
      final trimmed = value.trim();
      if (trimmed.isEmpty) {
        return;
      }
      grouped.putIfAbsent(sectionKey, () => []).add(
        AdvancedExifItem(
          key: key,
          value: trimmed,
          source: AdvancedExifValueSource.local,
        ),
      );
    }

    for (final entry in tags.entries) {
      final rawKey = entry.key;
      final sectionKey = _resolveSection(rawKey);
      final itemKey = _knownKey(rawKey) ?? _normalizeKey(rawKey);
      final value = _stringifyTag(entry.value);
      if (value == null || value.isEmpty) {
        continue;
      }
      put(sectionKey, itemKey, value);
    }

    final sections = grouped.entries
        .map((entry) => AdvancedExifSection(key: entry.key, items: entry.value))
        .where((section) => section.items.isNotEmpty)
        .toList();
    return AdvancedExifInfo(sections: sections);
  }

  String _resolveSection(String rawKey) {
    final knownKey = _knownKey(rawKey);
    if (knownKey != null) {
      return _sectionFromItemKey(knownKey);
    }
    if (rawKey.startsWith('GPS ')) {
      return 'advanced_exif_section_location';
    }
    if (rawKey.startsWith('EXIF ')) {
      return 'advanced_exif_section_camera';
    }
    if (rawKey.startsWith('Image ')) {
      return 'advanced_exif_section_image';
    }
    return 'advanced_exif_section_file';
  }

  String _sectionFromItemKey(String itemKey) {
    if (itemKey.startsWith('advanced_exif_location_')) {
      return 'advanced_exif_section_location';
    }
    if (itemKey.startsWith('advanced_exif_camera_') ||
        itemKey.startsWith('advanced_exif_lens_') ||
        itemKey.startsWith('advanced_exif_focal_') ||
        itemKey.startsWith('advanced_exif_aperture') ||
        itemKey.startsWith('advanced_exif_max_aperture') ||
        itemKey.startsWith('advanced_exif_exposure_') ||
        itemKey.startsWith('advanced_exif_shutter_') ||
        itemKey.startsWith('advanced_exif_subject_') ||
        itemKey.startsWith('advanced_exif_noise_') ||
        itemKey.startsWith('advanced_exif_scene_') ||
        itemKey.startsWith('advanced_exif_digital_') ||
        itemKey.startsWith('advanced_exif_metering_') ||
        itemKey.startsWith('advanced_exif_white_') ||
        itemKey.startsWith('advanced_exif_flash') ||
        itemKey.startsWith('advanced_exif_brightness') ||
        itemKey.startsWith('advanced_exif_contrast') ||
        itemKey.startsWith('advanced_exif_saturation') ||
        itemKey.startsWith('advanced_exif_sharpness')) {
      return 'advanced_exif_section_camera';
    }
    if (itemKey.startsWith('advanced_exif_image_') || itemKey == 'advanced_exif_orientation') {
      return 'advanced_exif_section_image';
    }
    if (itemKey.startsWith('advanced_exif_thumbnail_')) {
      return 'advanced_exif_section_file';
    }
    return 'advanced_exif_section_file';
  }

  String? _knownKey(String rawKey) {
    final key = rawKey.toLowerCase();
    return switch (key) {
      'image imagewidth' => 'advanced_exif_image_width',
      'image imagelength' => 'advanced_exif_image_height',
      'image orientation' => 'advanced_exif_orientation',
      'image software' => 'advanced_exif_software',
      'image artist' => 'advanced_exif_file_artist',
      'image copyright' => 'advanced_exif_file_copyright',
      'image hostcomputer' => 'advanced_exif_file_host_computer',
      'image imagedescription' => 'advanced_exif_file_description',
      'image datetime' => 'advanced_exif_date_time',
      'image make' => 'advanced_exif_camera_make',
      'image model' => 'advanced_exif_camera_model',
      'image xresolution' => 'advanced_exif_image_processing_xresolution',
      'image yresolution' => 'advanced_exif_image_processing_yresolution',
      'image resolutionunit' => 'advanced_exif_image_processing_resolution_unit',
      'exif datetimeoriginal' => 'advanced_exif_file_datetime_original',
      'exif createdate' => 'advanced_exif_create_date',
      'exif modifydate' => 'advanced_exif_file_modify_date',
      'exif timezoneoffset' => 'advanced_exif_timezone_offset',
      'exif exifimagewidth' => 'advanced_exif_image_width',
      'exif exifimagelength' => 'advanced_exif_image_height',
      'exif lensmodel' => 'advanced_exif_camera_lens',
      'exif lensid' => 'advanced_exif_lens_id',
      'exif lensserialnumber' => 'advanced_exif_lens_serial_number',
      'exif bodyserialnumber' => 'advanced_exif_camera_body_serial_number',
      'exif focallength' => 'advanced_exif_camera_focal_length',
      'exif focallengthin35mmfilm' => 'advanced_exif_focal_length_35mm',
      'exif fnumber' => 'advanced_exif_camera_fnumber',
      'exif aperturevalue' => 'advanced_exif_aperture',
      'exif maxaperturevalue' => 'advanced_exif_max_aperture',
      'exif iso' => 'advanced_exif_camera_iso',
      'exif exposuretime' => 'advanced_exif_exposure_time',
      'exif shutterspeedvalue' => 'advanced_exif_shutter_speed',
      'exif exposurecompensation' => 'advanced_exif_exposure_compensation',
      'exif exposureprogram' => 'advanced_exif_exposure_program',
      'exif exposuremode' => 'advanced_exif_camera_exposure_mode',
      'exif sensitivitytype' => 'advanced_exif_sensitivity_type',
      'exif recommendedexposureindex' => 'advanced_exif_recommended_exposure_index',
      'exif meteringmode' => 'advanced_exif_metering_mode',
      'exif lightsource' => 'advanced_exif_light_source',
      'exif whitebalance' => 'advanced_exif_white_balance',
      'exif flash' => 'advanced_exif_flash',
      'exif brightnessvalue' => 'advanced_exif_brightness',
      'exif contrast' => 'advanced_exif_contrast',
      'exif saturation' => 'advanced_exif_saturation',
      'exif sharpness' => 'advanced_exif_sharpness',
      'exif scenecapturetype' => 'advanced_exif_scene_capture_type',
      'exif digitalzoomratio' => 'advanced_exif_digital_zoom_ratio',
      'exif subjectdistance' => 'advanced_exif_subject_distance',
      'exif subjectdistancerange' => 'advanced_exif_subject_distance_range',
      'exif noisereduction' => 'advanced_exif_noise_reduction',
      'exif customrendered' => 'advanced_exif_custom_rendered',
      'exif gaincontrol' => 'advanced_exif_gain_control',
      'exif scenetype' => 'advanced_exif_scene_type',
      'exif sensingmethod' => 'advanced_exif_sensing_method',
      'exif filesource' => 'advanced_exif_file_source',
      'exif cameratemperature' => 'advanced_exif_camera_temperature',
      'gps gpslatitude' => 'advanced_exif_location_latitude',
      'gps gpslatituderef' => 'advanced_exif_location_latitude_ref',
      'gps gpslongitude' => 'advanced_exif_location_longitude',
      'gps gpslongituderef' => 'advanced_exif_location_longitude_ref',
      'gps gpsaltitude' => 'advanced_exif_location_altitude',
      'gps gpsaltituderef' => 'advanced_exif_location_altitude_ref',
      'gps gpsspeed' => 'advanced_exif_location_speed',
      'gps gpsimgdirection' => 'advanced_exif_location_img_direction',
      'gps gpsdestbearing' => 'advanced_exif_location_dest_bearing',
      'gps gpsdatestamp' => 'advanced_exif_location_date_stamp',
      'gps gpstimestamp' => 'advanced_exif_location_time_stamp',
      'gps gpsprocessingmethod' => 'advanced_exif_location_processing_method',
      'gps gpsmapdatum' => 'advanced_exif_location_map_datum',
      'gps gpshpositioningerror' => 'advanced_exif_location_h_positioning_error',
      'thumbnail jpeginterchangeformat' => 'advanced_exif_thumbnail_offset',
      'thumbnail jpeginterchangeformatlength' => 'advanced_exif_thumbnail_length',
      _ => null,
    };
  }

  String _normalizeKey(String rawKey) {
    final sanitized = rawKey.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]+'), '_');
    return 'advanced_exif_dynamic_$sanitized';
  }

  String? _stringifyTag(IfdTag tag) {
    final printable = tag.printable.trim();
    if (printable.isNotEmpty) {
      return printable;
    }
    final values = tag.values;
    final rendered = values.toString().trim();
    return rendered.isEmpty ? null : rendered;
  }

  Future<AdvancedExifInfo> _fallbackFromLegacyAsset(Asset asset, File file) async {
    final format = await _detectFormatFromFile(file);
    final sections = <AdvancedExifSection>[
      AdvancedExifSection(
        key: 'advanced_exif_section_image',
        items: [
          if (asset.width != null)
            AdvancedExifItem(
              key: 'advanced_exif_image_width',
              value: asset.width.toString(),
              source: AdvancedExifValueSource.local,
            ),
          if (asset.height != null)
            AdvancedExifItem(
              key: 'advanced_exif_image_height',
              value: asset.height.toString(),
              source: AdvancedExifValueSource.local,
            ),
        ],
      ),
      AdvancedExifSection(
        key: 'advanced_exif_section_location',
        items: [
          if (asset.exifInfo?.latitude != null)
            AdvancedExifItem(
              key: 'advanced_exif_location_latitude',
              value: asset.exifInfo!.latitude!.toString(),
              source: AdvancedExifValueSource.local,
            ),
          if (asset.exifInfo?.longitude != null)
            AdvancedExifItem(
              key: 'advanced_exif_location_longitude',
              value: asset.exifInfo!.longitude!.toString(),
              source: AdvancedExifValueSource.local,
            ),
        ],
      ),
      AdvancedExifSection(
        key: 'advanced_exif_section_file',
        items: [
          AdvancedExifItem(
            key: 'advanced_exif_file_name',
            value: asset.fileName,
            source: AdvancedExifValueSource.local,
          ),
          AdvancedExifItem(
            key: 'advanced_exif_file_type_extension',
            value: _extensionFromPath(file.path),
            source: AdvancedExifValueSource.local,
          ),
          AdvancedExifItem(
            key: 'advanced_exif_image_type',
            value: format,
            source: AdvancedExifValueSource.local,
          ),
          AdvancedExifItem(
            key: 'advanced_exif_file_size_bytes',
            value: file.lengthSync().toString(),
            source: AdvancedExifValueSource.local,
          ),
        ],
      ),
    ];
    return AdvancedExifInfo(sections: sections.where((s) => s.items.isNotEmpty).toList());
  }

  Future<AdvancedExifInfo> _fallbackFromBaseAsset(BaseAsset asset, AssetEntity entity, File file) async {
    final format = await _detectFormatFromFile(file);
    final sections = <AdvancedExifSection>[
      AdvancedExifSection(
        key: 'advanced_exif_section_image',
        items: [
          if (asset.width != null)
            AdvancedExifItem(
              key: 'advanced_exif_image_width',
              value: asset.width.toString(),
              source: AdvancedExifValueSource.local,
            ),
          if (asset.height != null)
            AdvancedExifItem(
              key: 'advanced_exif_image_height',
              value: asset.height.toString(),
              source: AdvancedExifValueSource.local,
            ),
          AdvancedExifItem(
            key: 'advanced_exif_orientation',
            value: entity.orientation.toString(),
            source: AdvancedExifValueSource.local,
          ),
        ],
      ),
      AdvancedExifSection(
        key: 'advanced_exif_section_location',
        items: [
          if (entity.latitude != null)
            AdvancedExifItem(
              key: 'advanced_exif_location_latitude',
              value: entity.latitude!.toString(),
              source: AdvancedExifValueSource.local,
            ),
          if (entity.longitude != null)
            AdvancedExifItem(
              key: 'advanced_exif_location_longitude',
              value: entity.longitude!.toString(),
              source: AdvancedExifValueSource.local,
            ),
        ],
      ),
      AdvancedExifSection(
        key: 'advanced_exif_section_file',
        items: [
          AdvancedExifItem(
            key: 'advanced_exif_file_name',
            value: asset.name,
            source: AdvancedExifValueSource.local,
          ),
          AdvancedExifItem(
            key: 'advanced_exif_file_type_extension',
            value: _extensionFromPath(file.path),
            source: AdvancedExifValueSource.local,
          ),
          AdvancedExifItem(
            key: 'advanced_exif_image_type',
            value: format,
            source: AdvancedExifValueSource.local,
          ),
          AdvancedExifItem(
            key: 'advanced_exif_file_datetime_original',
            value: entity.createDateTime.toIso8601String(),
            source: AdvancedExifValueSource.local,
          ),
          AdvancedExifItem(
            key: 'advanced_exif_file_modify_date',
            value: entity.modifiedDateTime.toIso8601String(),
            source: AdvancedExifValueSource.local,
          ),
          AdvancedExifItem(
            key: 'advanced_exif_file_size_bytes',
            value: file.lengthSync().toString(),
            source: AdvancedExifValueSource.local,
          ),
          if (asset.durationInSeconds != null)
            AdvancedExifItem(
              key: 'advanced_exif_dynamic_media_duration_seconds',
              value: asset.durationInSeconds.toString(),
              source: AdvancedExifValueSource.local,
            ),
        ],
      ),
    ];
    return AdvancedExifInfo(sections: sections.where((s) => s.items.isNotEmpty).toList());
  }

  String _extensionFromPath(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0 || dot == path.length - 1) {
      return 'unknown';
    }
    return path.substring(dot + 1).toLowerCase();
  }

  Future<String> _detectFormatFromFile(File file) async {
    try {
      final header = await file.openRead(0, 32).expand((chunk) => chunk).take(32).toList();
      if (_isJpeg(header)) return 'JPEG';
      if (_isPng(header)) return 'PNG';
      if (_isWebp(header)) return 'WEBP';
      if (_isIsobmff(header)) return 'HEIC/MP4';
    } catch (_) {
      // Fall back to extension-based format detection below.
    }
    return switch (_extensionFromPath(file.path)) {
      'jpg' || 'jpeg' => 'JPEG',
      'png' => 'PNG',
      'webp' => 'WEBP',
      'heic' || 'heif' => 'HEIC',
      'mp4' => 'MP4',
      'mov' => 'MOV',
      final ext => ext.toUpperCase(),
    };
  }

  bool _isJpeg(List<int> bytes) => bytes.length >= 3 && bytes[0] == 0xFF && bytes[1] == 0xD8 && bytes[2] == 0xFF;

  bool _isPng(List<int> bytes) =>
      bytes.length >= 8 &&
      bytes[0] == 0x89 &&
      bytes[1] == 0x50 &&
      bytes[2] == 0x4E &&
      bytes[3] == 0x47 &&
      bytes[4] == 0x0D &&
      bytes[5] == 0x0A &&
      bytes[6] == 0x1A &&
      bytes[7] == 0x0A;

  bool _isWebp(List<int> bytes) =>
      bytes.length >= 12 &&
      bytes[0] == 0x52 &&
      bytes[1] == 0x49 &&
      bytes[2] == 0x46 &&
      bytes[3] == 0x46 &&
      bytes[8] == 0x57 &&
      bytes[9] == 0x45 &&
      bytes[10] == 0x42 &&
      bytes[11] == 0x50;

  bool _isIsobmff(List<int> bytes) =>
      bytes.length >= 12 &&
      bytes[4] == 0x66 &&
      bytes[5] == 0x74 &&
      bytes[6] == 0x79 &&
      bytes[7] == 0x70;

}
