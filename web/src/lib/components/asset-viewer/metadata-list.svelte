<script lang="ts">
  import cameraDarkIcon from '$lib/assets/camera-dark.svg';
  import cameraIcon from '$lib/assets/camera.svg';
  import fileInfoDarkIcon from '$lib/assets/file-info-dark.svg';
  import fileInfoIcon from '$lib/assets/file-info.svg';
  import galleryThumbnailDarkIcon from '$lib/assets/gallery-thumbnail-dark.svg';
  import galleryThumbnailIcon from '$lib/assets/gallery-thumbnail.svg';
  import photoInfoDarkIcon from '$lib/assets/photo-info-dark.svg';
  import photoInfoIcon from '$lib/assets/photo-info.svg';
  import photoSettingsDarkIcon from '$lib/assets/photo-settings-dark.svg';
  import photoSettingsIcon from '$lib/assets/photo-settings.svg';
  import settingsPhotoCameraDarkIcon from '$lib/assets/settings-photo-camera-dark.svg';
  import settingsPhotoCameraIcon from '$lib/assets/settings-photo-camera.svg';
  import MetadataAccordion from '$lib/components/asset-viewer/metadata-accordion.svelte';
  import MetadataListItems from '$lib/components/asset-viewer/metadata-list-items.svelte';
  import { QueryParameter } from '$lib/constants';
  import { themeManager } from '$lib/managers/theme-manager.svelte';
  import { locale } from '$lib/stores/preferences.store';
  import { convertOrientationValue } from '$lib/utils';
  import { fromISODateTime, fromISODateTimeUTC } from '$lib/utils/timeline-util';
  import type { ExifResponseDto } from '@immich/sdk';
  import { Theme } from '@immich/ui';
  import { mdiCalendar, mdiCrosshairsGps, mdiTune } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import SettingAccordionState from '../shared-components/settings/setting-accordion-state.svelte';

  interface Props {
    exifInfo?: ExifResponseDto;
  }

  let { exifInfo }: Props = $props();

  const theme = $derived(themeManager.value);

  let timeZone = $derived(exifInfo?.timeZone);
  let dateTime = $derived(
    exifInfo?.dateTimeOriginal
      ? timeZone
        ? fromISODateTime(exifInfo.dateTimeOriginal, timeZone)
        : fromISODateTimeUTC(exifInfo.dateTimeOriginal)
      : '',
  );
</script>

<SettingAccordionState queryParam={QueryParameter.IS_OPEN}>
  <MetadataAccordion
    src={theme === Theme.Light ? photoInfoIcon : photoInfoDarkIcon}
    key="image-information"
    title={$t('metadata_info.image_information')}
    length={12}
  >
    <MetadataListItems
      items={[
        { title: $t('metadata_info.image_width'), value: exifInfo?.exifImageWidth },
        { title: $t('metadata_info.image_height'), value: exifInfo?.exifImageHeight },
        { title: $t('metadata_info.image_description'), value: exifInfo?.description },
        { title: $t('metadata_info.make'), value: exifInfo?.make },
        { title: $t('metadata_info.model'), value: exifInfo?.model },
        {
          title: $t('metadata_info.orientation'),
          value: exifInfo?.orientation ? convertOrientationValue(exifInfo?.orientation) : undefined,
        },
        { title: $t('metadata_info.software'), value: exifInfo?.software },
        { title: $t('metadata_info.artist'), value: exifInfo?.artist },
        { title: $t('metadata_info.copyright'), value: exifInfo?.copyright },
        { title: $t('metadata_info.x_resolution'), value: exifInfo?.xResolution },
        { title: $t('metadata_info.y_resolution'), value: exifInfo?.yResolution },
        { title: $t('metadata_info.resolution_unit'), value: exifInfo?.resolutionUnit },
      ]}
    />
  </MetadataAccordion>

  <MetadataAccordion icon={mdiCalendar} key="date-and-time" title={$t('metadata_info.date_and_time')} length={9}>
    <MetadataListItems
      items={[
        {
          title: $t('metadata_info.date_time'),
          value: exifInfo?.dateTimeOriginal
            ? dateTime.toLocaleString(
                {
                  month: 'short',
                  day: 'numeric',
                  year: 'numeric',
                  hour: 'numeric',
                  minute: 'numeric',
                  second: 'numeric',
                },
                { locale: $locale },
              )
            : '',
        },
        { title: $t('metadata_info.date_time_original'), value: exifInfo?.dateTimeOriginal },
        {
          title: $t('metadata_info.date_time_digitized'),
          value: exifInfo?.dateTimeOriginal
            ? dateTime.toLocaleString(
                {
                  month: 'numeric',
                  day: 'numeric',
                  year: 'numeric',
                  hour: 'numeric',
                  minute: 'numeric',
                  second: 'numeric',
                },
                { locale: $locale },
              )
            : '',
        },
        { title: $t('metadata_info.sub_sec_time'), value: exifInfo?.subSecTime },
        { title: $t('metadata_info.sub_sec_time_original'), value: exifInfo?.subSecTimeOriginal },
        {
          title: $t('metadata_info.sub_sec_time_digitized'),
          value: exifInfo?.subSecTimeDigitized,
        },
        { title: $t('metadata_info.offset_time'), value: exifInfo?.offsetTime },
        { title: $t('metadata_info.offset_time_original'), value: exifInfo?.offsetTimeOriginal },
        { title: $t('metadata_info.offset_time_digitized'), value: exifInfo?.offsetTimeDigitized },
      ]}
    />
  </MetadataAccordion>

  <MetadataAccordion
    src={theme === Theme.Light ? settingsPhotoCameraIcon : settingsPhotoCameraDarkIcon}
    key="camera-settings"
    title={$t('metadata_info.camera_settings')}
  ></MetadataAccordion>

  <MetadataAccordion
    src={theme === Theme.Light ? cameraIcon : cameraDarkIcon}
    key="lens-and-focal-length"
    title={$t('metadata_info.lens_and_focal_length')}
  ></MetadataAccordion>

  <MetadataAccordion
    src={theme === Theme.Light ? photoSettingsIcon : photoSettingsDarkIcon}
    key="image-processing"
    title={$t('metadata_info.image_processing')}
  ></MetadataAccordion>

  <MetadataAccordion icon={mdiCrosshairsGps} key="gps-data" title={$t('metadata_info.gps_data')}></MetadataAccordion>

  <MetadataAccordion
    src={theme === Theme.Light ? fileInfoIcon : fileInfoDarkIcon}
    key="file-information"
    title={$t('metadata_info.file_information')}
  ></MetadataAccordion>

  <MetadataAccordion icon={mdiTune} key="advanced-settings" title={$t('metadata_info.advanced_settings')}
  ></MetadataAccordion>

  <MetadataAccordion
    src={theme === Theme.Light ? galleryThumbnailIcon : galleryThumbnailDarkIcon}
    key="thumbnail"
    title={$t('metadata_info.thumbnail')}
  ></MetadataAccordion>
</SettingAccordionState>
