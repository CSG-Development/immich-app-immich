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
  import { QueryParameter } from '$lib/constants';
  import { themeManager } from '$lib/managers/theme-manager.svelte';
  import { Theme } from '@immich/ui';
  import { mdiCalendar, mdiCrosshairsGps, mdiTune } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import SettingAccordionState from '../shared-components/settings/setting-accordion-state.svelte';

  const theme = $derived(themeManager.value);
</script>

<SettingAccordionState queryParam={QueryParameter.IS_OPEN}>
  <MetadataAccordion
    src={theme === Theme.Light ? photoInfoIcon : photoInfoDarkIcon}
    key="image-information"
    title={$t('metadata_info.image_information')}
  ></MetadataAccordion>

  <MetadataAccordion icon={mdiCalendar} key="date-and-time" title={$t('metadata_info.date_and_time')}
  ></MetadataAccordion>

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
