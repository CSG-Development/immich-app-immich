<script lang="ts">
  import Camera from '$lib/assets/camera.svelte';
  import FileInfo from '$lib/assets/file-info.svelte';
  import GalleryThumbnail from '$lib/assets/gallery-thumbnail.svelte';
  import PhotoInfo from '$lib/assets/photo-info.svelte';
  import PhotoSettings from '$lib/assets/photo-settings.svelte';
  import SettingsPhotoCamera from '$lib/assets/settings-photo-camera.svelte';
  import MetadataAccordion from '$lib/components/asset-viewer/metadata-accordion.svelte';
  import MetadataListItems from '$lib/components/asset-viewer/metadata-list-items.svelte';
  import { QueryParameter } from '$lib/constants';
  import { locale } from '$lib/stores/preferences.store';
  import { convertOrientationValue } from '$lib/utils';
  import { fromISODateTime, fromISODateTimeUTC } from '$lib/utils/timeline-util';
  import type { ExifResponseDto } from '@immich/sdk';
  import { mdiCalendar, mdiCrosshairsGps, mdiTune } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import SettingAccordionState from '../shared-components/settings/setting-accordion-state.svelte';

  interface Props {
    exifInfo?: ExifResponseDto;
  }

  let { exifInfo }: Props = $props();

  let timeZone = $derived(exifInfo?.timeZone);
  let dateTime = $derived(
    exifInfo?.dateTimeOriginal
      ? timeZone
        ? fromISODateTime(exifInfo.dateTimeOriginal, timeZone)
        : fromISODateTimeUTC(exifInfo.dateTimeOriginal)
      : '',
  );
  let subSecTime = $derived(
    exifInfo?.subSecTime
      ? timeZone
        ? fromISODateTime(exifInfo.subSecTime, timeZone)
        : fromISODateTimeUTC(exifInfo.subSecTime)
      : '',
  );
  let offsetTime = $derived(
    exifInfo?.offsetTime
      ? timeZone
        ? fromISODateTime(exifInfo.offsetTime, timeZone)
        : fromISODateTimeUTC(exifInfo.offsetTime)
      : '',
  );

  const imageInformation = $derived([
    ...(exifInfo?.exifImageWidth
      ? [{ title: $t('metadata_info.image_width'), value: `${exifInfo?.exifImageWidth} ${$t('pixels')}` }]
      : []),
    ...(exifInfo?.exifImageHeight
      ? [{ title: $t('metadata_info.image_height'), value: `${exifInfo?.exifImageHeight} ${$t('pixels')}` }]
      : []),
    ...(exifInfo?.description ? [{ title: $t('metadata_info.image_description'), value: exifInfo?.description }] : []),
    ...(exifInfo?.make ? [{ title: $t('metadata_info.make'), value: exifInfo?.make }] : []),
    ...(exifInfo?.model ? [{ title: $t('metadata_info.model'), value: exifInfo?.model }] : []),
    ...(exifInfo?.orientation
      ? [
          {
            title: $t('metadata_info.orientation'),
            value: exifInfo?.orientation ? convertOrientationValue(exifInfo?.orientation) : undefined,
          },
        ]
      : []),
    ...(exifInfo?.software ? [{ title: $t('metadata_info.software'), value: exifInfo?.software }] : []),
    ...(exifInfo?.artist ? [{ title: $t('metadata_info.artist'), value: exifInfo?.artist }] : []),
    ...(exifInfo?.copyright ? [{ title: $t('metadata_info.copyright'), value: exifInfo?.copyright }] : []),
    ...(exifInfo?.xResolution ? [{ title: $t('metadata_info.x_resolution'), value: exifInfo?.xResolution }] : []),
    ...(exifInfo?.yResolution ? [{ title: $t('metadata_info.y_resolution'), value: exifInfo?.yResolution }] : []),
    ...(exifInfo?.resolutionUnit
      ? [{ title: $t('metadata_info.resolution_unit'), value: exifInfo?.resolutionUnit }]
      : []),
  ]);

  const dateAndTime = $derived([
    ...(exifInfo?.dateTimeOriginal
      ? [
          {
            title: $t('metadata_info.date_time'),
            value: dateTime.toLocaleString(
              {
                month: 'short',
                day: 'numeric',
                year: 'numeric',
                hour: 'numeric',
                minute: 'numeric',
                second: 'numeric',
              },
              { locale: $locale },
            ),
          },
          { title: $t('metadata_info.date_time_original'), value: exifInfo?.dateTimeOriginal },
          {
            title: $t('metadata_info.date_time_digitized'),
            value: dateTime.toLocaleString(
              {
                month: 'numeric',
                day: 'numeric',
                year: 'numeric',
                hour: 'numeric',
                minute: 'numeric',
                second: 'numeric',
              },
              { locale: $locale },
            ),
          },
        ]
      : []),
    ...(exifInfo?.subSecTime
      ? [
          {
            title: $t('metadata_info.sub_sec_time'),
            value: subSecTime.toLocaleString(
              {
                month: 'short',
                day: 'numeric',
                year: 'numeric',
                hour: 'numeric',
                minute: 'numeric',
                second: 'numeric',
              },
              { locale: $locale },
            ),
          },
          { title: $t('metadata_info.sub_sec_time_original'), value: exifInfo?.subSecTime },
          {
            title: $t('metadata_info.sub_sec_time_digitized'),
            value: subSecTime.toLocaleString(
              {
                month: 'numeric',
                day: 'numeric',
                year: 'numeric',
                hour: 'numeric',
                minute: 'numeric',
                second: 'numeric',
              },
              { locale: $locale },
            ),
          },
        ]
      : []),

    ...(exifInfo?.offsetTime
      ? [
          {
            title: $t('metadata_info.offset_time'),
            value: offsetTime.toLocaleString(
              {
                month: 'short',
                day: 'numeric',
                year: 'numeric',
                hour: 'numeric',
                minute: 'numeric',
                second: 'numeric',
              },
              { locale: $locale },
            ),
          },
          { title: $t('metadata_info.offset_time_original'), value: exifInfo?.offsetTime },
          {
            title: $t('metadata_info.offset_time_digitized'),
            value: offsetTime.toLocaleString(
              {
                month: 'numeric',
                day: 'numeric',
                year: 'numeric',
                hour: 'numeric',
                minute: 'numeric',
                second: 'numeric',
              },
              { locale: $locale },
            ),
          },
        ]
      : []),
  ]);

  const cameraSettings = $derived([
    ...(exifInfo?.exposureTime
      ? [{ title: $t('metadata_info.exposure_time'), value: `${exifInfo?.exposureTime} sec` }]
      : []),
    ...(exifInfo?.fNumber ? [{ title: $t('metadata_info.f_number'), value: exifInfo?.fNumber }] : []),
    ...(exifInfo?.exposureProgram
      ? [{ title: $t('metadata_info.exposure_program'), value: exifInfo?.exposureProgram }]
      : []),
    ...(exifInfo?.iso ? [{ title: $t('metadata_info.iso_speed_ratings'), value: exifInfo?.iso }] : []),
    ...(exifInfo?.shutterSpeedValue
      ? [{ title: $t('metadata_info.shutter_speed_value'), value: exifInfo?.shutterSpeedValue }]
      : []),
    ...(exifInfo?.apertureValue ? [{ title: $t('metadata_info.aperture_value'), value: exifInfo?.apertureValue }] : []),
    ...(exifInfo?.brightnessValue
      ? [{ title: $t('metadata_info.brightness_value'), value: exifInfo?.brightnessValue }]
      : []),
    ...(exifInfo?.exposureBiasValue
      ? [{ title: $t('metadata_info.exposure_bias_value'), value: exifInfo?.exposureBiasValue }]
      : []),
    ...(exifInfo?.maxApertureValue
      ? [{ title: $t('metadata_info.max_aperture_value'), value: exifInfo?.maxApertureValue }]
      : []),
    ...(exifInfo?.meteringMode ? [{ title: $t('metadata_info.metering_mode'), value: exifInfo?.meteringMode }] : []),
    ...(exifInfo?.lightSource ? [{ title: $t('metadata_info.light_source'), value: exifInfo?.lightSource }] : []),
    ...(exifInfo?.flash ? [{ title: $t('metadata_info.flash'), value: exifInfo?.flash }] : []),
  ]);

  const lensAndFocalLength = $derived([
    ...(exifInfo?.focalLength
      ? [{ title: $t('metadata_info.focal_length'), value: `${exifInfo?.focalLength} mm` }]
      : []),
    ...(exifInfo?.focalLengthIn35mmFilm
      ? [{ title: $t('metadata_info.focal_length_in_35mm_film'), value: exifInfo?.focalLengthIn35mmFilm }]
      : []),
    ...(exifInfo?.lensMake ? [{ title: $t('metadata_info.lens_make'), value: exifInfo?.lensMake }] : []),
    ...(exifInfo?.lensModel ? [{ title: $t('metadata_info.lens_model'), value: exifInfo?.lensModel }] : []),
    ...(exifInfo?.lensSerialNumber
      ? [{ title: $t('metadata_info.lens_serial_number'), value: exifInfo?.lensSerialNumber }]
      : []),
    ...(exifInfo?.lensSpecification
      ? [{ title: $t('metadata_info.lens_specification'), value: exifInfo?.lensSpecification }]
      : []),
  ]);

  const imageProcessing = $derived([
    ...(exifInfo?.whiteBalance ? [{ title: $t('metadata_info.white_balance'), value: exifInfo?.whiteBalance }] : []),
    ...(exifInfo?.digitalZoomRatio
      ? [{ title: $t('metadata_info.digital_zoom_ratio'), value: exifInfo?.digitalZoomRatio }]
      : []),
    ...(exifInfo?.sceneCaptureType
      ? [{ title: $t('metadata_info.scene_capture_type'), value: exifInfo?.sceneCaptureType }]
      : []),
    ...(exifInfo?.gainControl ? [{ title: $t('metadata_info.gain_control'), value: exifInfo?.gainControl }] : []),
    ...(exifInfo?.contrast ? [{ title: $t('metadata_info.contrast'), value: exifInfo?.contrast }] : []),
    ...(exifInfo?.saturation ? [{ title: $t('metadata_info.saturation'), value: exifInfo?.saturation }] : []),
    ...(exifInfo?.sharpness ? [{ title: $t('metadata_info.sharpness'), value: exifInfo?.sharpness }] : []),
    ...(exifInfo?.subjectDistanceRange
      ? [{ title: $t('metadata_info.subject_distance_range'), value: exifInfo?.subjectDistanceRange }]
      : []),
    ...(exifInfo?.colorSpace ? [{ title: $t('metadata_info.color_space'), value: exifInfo?.colorSpace }] : []),
    ...(exifInfo?.sensingMethod ? [{ title: $t('metadata_info.sensing_method'), value: exifInfo?.sensingMethod }] : []),
  ]);

  const gpsData = $derived([
    ...(exifInfo?.gpsVersionId ? [{ title: $t('metadata_info.gps_version_id'), value: exifInfo?.gpsVersionId }] : []),
    ...(exifInfo?.gpsLatitudeRef
      ? [{ title: $t('metadata_info.gps_latitude_ref'), value: exifInfo?.gpsLatitudeRef }]
      : []),
    ...(exifInfo?.gpsLatitude ? [{ title: $t('metadata_info.gps_latitude'), value: exifInfo?.gpsLatitude }] : []),
    ...(exifInfo?.gpsLongitudeRef
      ? [{ title: $t('metadata_info.gps_longitude_ref'), value: exifInfo?.gpsLongitudeRef }]
      : []),
    ...(exifInfo?.gpsLongitude ? [{ title: $t('metadata_info.gps_longitude'), value: exifInfo?.gpsLongitude }] : []),
    ...(exifInfo?.gpsAltitudeRef
      ? [{ title: $t('metadata_info.gps_altitude_ref'), value: exifInfo?.gpsAltitudeRef }]
      : []),
    ...(exifInfo?.gpsAltitude ? [{ title: $t('metadata_info.gps_altitude'), value: exifInfo?.gpsAltitude }] : []),
    ...(exifInfo?.gpsTimeStamp ? [{ title: $t('metadata_info.gps_time_stamp'), value: exifInfo?.gpsTimeStamp }] : []),
    ...(exifInfo?.gpsSpeedRef ? [{ title: $t('metadata_info.gps_speed_ref'), value: exifInfo?.gpsSpeedRef }] : []),
    ...(exifInfo?.gpsSpeed ? [{ title: $t('metadata_info.gps_speed'), value: exifInfo?.gpsSpeed }] : []),
    ...(exifInfo?.gpsDateStamp ? [{ title: $t('metadata_info.gps_date_stamp'), value: exifInfo?.gpsDateStamp }] : []),
  ]);

  const fileInformation = $derived([
    ...(exifInfo?.compression ? [{ title: $t('metadata_info.compression'), value: exifInfo?.compression }] : []),
    ...(exifInfo?.bitsPerSample
      ? [{ title: $t('metadata_info.bits_per_sample'), value: exifInfo?.bitsPerSample }]
      : []),
    ...(exifInfo?.photometricInterpretation
      ? [{ title: $t('metadata_info.photometric_interpretation'), value: exifInfo?.photometricInterpretation }]
      : []),
    ...(exifInfo?.samplesPerPixel
      ? [{ title: $t('metadata_info.samples_per_pixel'), value: exifInfo?.samplesPerPixel }]
      : []),
    ...(exifInfo?.planarConfiguration
      ? [{ title: $t('metadata_info.planar_configuration'), value: exifInfo?.planarConfiguration }]
      : []),
    ...(exifInfo?.ycbcrSubSampling
      ? [{ title: $t('metadata_info.ycbcr_sub_sampling'), value: exifInfo?.ycbcrSubSampling }]
      : []),
    ...(exifInfo?.ycbcrPositioning
      ? [{ title: $t('metadata_info.ycbcr_positioning'), value: exifInfo?.ycbcrPositioning }]
      : []),
    ...(exifInfo?.referenceBlackWhite
      ? [{ title: $t('metadata_info.reference_black_white'), value: exifInfo?.referenceBlackWhite }]
      : []),
  ]);

  const advancedSettings = $derived([
    ...(exifInfo?.exifVersion ? [{ title: $t('metadata_info.exif_version'), value: exifInfo?.exifVersion }] : []),
    ...(exifInfo?.flashpixVersion
      ? [{ title: $t('metadata_info.flashpix_version'), value: exifInfo?.flashpixVersion }]
      : []),
    ...(exifInfo?.componentsConfiguration
      ? [{ title: $t('metadata_info.components_configuration'), value: exifInfo?.componentsConfiguration }]
      : []),
    ...(exifInfo?.compressedBitsPerPixel
      ? [{ title: $t('metadata_info.compressed_bits_per_pixel'), value: exifInfo?.compressedBitsPerPixel }]
      : []),
    ...(exifInfo?.makerNote ? [{ title: $t('metadata_info.maker_note'), value: exifInfo?.makerNote }] : []),
    ...(exifInfo?.userComment ? [{ title: $t('metadata_info.user_comment'), value: exifInfo?.userComment }] : []),
    ...(exifInfo?.subjectArea ? [{ title: $t('metadata_info.subject_area'), value: exifInfo?.subjectArea }] : []),
    ...(exifInfo?.subjectDistance
      ? [{ title: $t('metadata_info.subject_distance'), value: exifInfo?.subjectDistance }]
      : []),
    ...(exifInfo?.subjectLocation
      ? [{ title: $t('metadata_info.subject_location'), value: exifInfo?.subjectLocation }]
      : []),
    ...(exifInfo?.fileSource ? [{ title: $t('metadata_info.file_source'), value: exifInfo?.fileSource }] : []),
    ...(exifInfo?.sceneType ? [{ title: $t('metadata_info.scene_type'), value: exifInfo?.sceneType }] : []),
    ...(exifInfo?.cfaPattern ? [{ title: $t('metadata_info.cfa_pattern'), value: exifInfo?.cfaPattern }] : []),
    ...(exifInfo?.customRendered
      ? [{ title: $t('metadata_info.custom_rendered'), value: exifInfo?.customRendered }]
      : []),
    ...(exifInfo?.exposureMode ? [{ title: $t('metadata_info.exposure_mode'), value: exifInfo?.exposureMode }] : []),
    ...(exifInfo?.exposureIndex ? [{ title: $t('metadata_info.exposure_index'), value: exifInfo?.exposureIndex }] : []),
  ]);

  const thumbnail = $derived([
    ...(exifInfo?.thumbnailCompression
      ? [{ title: $t('metadata_info.thumbnail_compression'), value: exifInfo?.thumbnailCompression }]
      : []),
    ...(exifInfo?.thumbnailXResolution
      ? [{ title: $t('metadata_info.thumbnail_x_resolution'), value: exifInfo?.thumbnailXResolution }]
      : []),
    ...(exifInfo?.thumbnailYResolution
      ? [{ title: $t('metadata_info.thumbnail_y_resolution'), value: exifInfo?.thumbnailYResolution }]
      : []),
    ...(exifInfo?.thumbnailResolutionUnit
      ? [{ title: $t('metadata_info.thumbnail_resolution_unit'), value: exifInfo?.thumbnailResolutionUnit }]
      : []),
    ...(exifInfo?.thumbnailOffset
      ? [{ title: $t('metadata_info.thumbnail_offset'), value: exifInfo?.thumbnailOffset }]
      : []),
    ...(exifInfo?.thumbnailLength
      ? [{ title: $t('metadata_info.thumbnail_length'), value: exifInfo?.thumbnailLength }]
      : []),
  ]);
</script>

<SettingAccordionState queryParam={QueryParameter.IS_OPEN}>
  <MetadataAccordion
    icon={PhotoInfo}
    key="image-information"
    title={$t('metadata_info.image_information')}
    length={imageInformation.length}
  >
    <MetadataListItems items={imageInformation} />
  </MetadataAccordion>

  <MetadataAccordion
    icon={mdiCalendar}
    key="date-and-time"
    title={$t('metadata_info.date_and_time')}
    length={dateAndTime.length}
  >
    <MetadataListItems items={dateAndTime} />
  </MetadataAccordion>

  <MetadataAccordion
    icon={SettingsPhotoCamera}
    key="camera-settings"
    title={$t('metadata_info.camera_settings')}
    length={cameraSettings.length}
  >
    <MetadataListItems items={cameraSettings} />
  </MetadataAccordion>

  <MetadataAccordion
    icon={Camera}
    key="lens-and-focal-length"
    title={$t('metadata_info.lens_and_focal_length')}
    length={lensAndFocalLength.length}
  >
    <MetadataListItems items={lensAndFocalLength} />
  </MetadataAccordion>

  <MetadataAccordion
    icon={PhotoSettings}
    key="image-processing"
    title={$t('metadata_info.image_processing')}
    length={imageProcessing.length}
  >
    <MetadataListItems items={imageProcessing} />
  </MetadataAccordion>

  <MetadataAccordion
    icon={mdiCrosshairsGps}
    key="gps-data"
    title={$t('metadata_info.gps_data')}
    length={gpsData.length}
  >
    <MetadataListItems items={gpsData} />
  </MetadataAccordion>

  <MetadataAccordion
    icon={FileInfo}
    key="file-information"
    title={$t('metadata_info.file_information')}
    length={fileInformation.length}
  >
    <MetadataListItems items={fileInformation} />
  </MetadataAccordion>

  <MetadataAccordion
    icon={mdiTune}
    key="advanced-settings"
    title={$t('metadata_info.advanced_settings')}
    length={advancedSettings.length}
  >
    <MetadataListItems items={advancedSettings} />
  </MetadataAccordion>

  <MetadataAccordion
    icon={GalleryThumbnail}
    key="thumbnail"
    title={$t('metadata_info.thumbnail')}
    length={thumbnail.length}
  >
    <MetadataListItems items={thumbnail} />
  </MetadataAccordion>
</SettingAccordionState>
