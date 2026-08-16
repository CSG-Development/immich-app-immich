<script lang="ts">
  import { isDefined } from '$lib';
  import empty5Url from '$lib/assets/empty-5.svg';
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/empty-placeholder.svelte';
  import Timeline from '$lib/components/timeline/Timeline.svelte';
  import { AssetAction } from '$lib/constants';
  import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import type { TimelineDay } from '$lib/managers/timeline-manager/timeline-day.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import GeolocationPointPickerModal from '$lib/modals/GeolocationPointPickerModal.svelte';
  import GeolocationUpdateConfirmModal from '$lib/modals/GeolocationUpdateConfirmModal.svelte';
  import type { LatLng } from '$lib/types';
  import { setQueryValue } from '$lib/utils/navigation';
  import { formatPageTitleWithCount } from '$lib/utils/string-utils';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import { AssetVisibility, getAssetInfo, updateAssets } from '@immich/sdk';
  import { Button, LoadingSpinner, modalManager, Text } from '@immich/ui';
  import { mdiMapMarkerMultipleOutline, mdiPencilOutline, mdiSelectRemove } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import { locale } from '$lib/stores/preferences.store';
  import type { PageData } from './$types';

  type Props = {
    data: PageData;
  };

  let { data }: Props = $props();

  let isLoading = $state(false);
  let point = $state<LatLng>();
  let locationUpdated = $state(false);

  let timelineManager = $state<TimelineManager>() as TimelineManager;
  const options = {
    visibility: AssetVisibility.Timeline,
    withStacked: true,
    withPartners: true,
    withCoordinates: true,
  };

  const handleUpdate = async () => {
    if (!point) {
      return;
    }

    const confirmed = await modalManager.show(GeolocationUpdateConfirmModal, {
      point,
      assetCount: assetMultiSelectManager.assets.length,
    });

    if (!confirmed) {
      return;
    }

    const selectedIds = assetMultiSelectManager.selectedAssets.map((asset) => asset.id);

    await updateAssets({
      assetBulkUpdateDto: {
        ids: selectedIds,
        latitude: point.lat,
        longitude: point.lng,
      },
    });

    const updatedAssets = await Promise.all(
      assetMultiSelectManager.selectedAssets.map(async (asset) => {
        const updatedAsset = await getAssetInfo({ ...authManager.params, id: asset.id });
        return toTimelineAsset(updatedAsset);
      }),
    );

    timelineManager.upsertAssets(updatedAssets);

    assetMultiSelectManager.clear();
  };

  const onKeyDown = (event: KeyboardEvent) => {
    if (event.key === 'Shift') {
      event.preventDefault();
    }
    if (event.key === 'Escape' && assetMultiSelectManager.selectionActive) {
      assetMultiSelectManager.clear();
    }
  };
  const onKeyUp = (event: KeyboardEvent) => {
    if (event.key === 'Shift') {
      event.preventDefault();
    }
  };

  const handlePickPoint = async () => {
    const selected = await modalManager.show(GeolocationPointPickerModal, { point });
    if (!selected) {
      return;
    }

    point = selected;
  };
  const handleEscape = () => {
    if (assetMultiSelectManager.selectionActive) {
      assetMultiSelectManager.clear();
      return;
    }
  };

  type AssetPoint = { latitude: number; longitude: number };

  const hasGps = (asset: TimelineAsset | AssetPoint): asset is AssetPoint =>
    isDefined(asset.latitude) && isDefined(asset.longitude);

  const handleThumbnailClick = (
    asset: TimelineAsset,
    timelineManager: TimelineManager,
    timelineDay: TimelineDay,
    onClick: (
      timelineManager: TimelineManager,
      assets: TimelineAsset[],
      groupTitle: string,
      asset: TimelineAsset,
    ) => void,
  ) => {
    if (hasGps(asset)) {
      locationUpdated = true;
      setTimeout(() => {
        locationUpdated = false;
      }, 1500);
      point = { lat: asset.latitude, lng: asset.longitude };
      void setQueryValue('at', asset.id);
    } else {
      onClick(timelineManager, timelineDay.getAssets(), timelineDay.groupTitle, asset);
    }
  };

  let isEmpty = $derived(timelineManager.isInitialized && timelineManager.months.length === 0);
</script>

<svelte:document onkeydown={onKeyDown} onkeyup={onKeyUp} />

<UserPageLayout
  title={data.meta.title}
  scrollbar={true}
>
  {#snippet buttons()}
    <div class="flex gap-2 justify-end place-items-center">
      {#if !isEmpty}
        <Text class="hidden md:block text-xs mr-4 text-dark/50 max-h-10 overflow-auto"
          >{$t('geolocation_instruction_location')}</Text
        >
      {/if}
      <div class="flex place-items-center place-content-center px-2 py-1 bg-primary/10 rounded-2xl">
        <Text
          class="hidden md:inline-block text-xs text-immich-gray-text dark:text-immich-dark-gray-text mr-5 ml-2 uppercase"
        >
          {$t('selected_gps_coordinates')}
        </Text>
        <Text
          class="rounded-3xl text-xs text-primary-700 px-2 py-1 transition-all duration-100 ease-in-out {locationUpdated
            ? 'bg-primary/90 text-light font-semibold scale-105'
            : ''}"
          title={`${$t('latitude')}, ${$t('longitude')}`}
        >
          {#if point}
            {point.lat.toFixed(3)}, {point.lng.toFixed(3)}
          {:else}
            {$t('none')}
          {/if}
        </Text>
      </div>

      <Button size="small" color="secondary" variant="ghost" leadingIcon={mdiPencilOutline} onclick={handlePickPoint}>
        <Text class="hidden sm:inline-block font-medium">{$t('location_picker_choose_on_map')}</Text>
      </Button>
      {#if !isEmpty}
        <Button
          leadingIcon={mdiSelectRemove}
          size="small"
          color="secondary"
          variant="ghost"
          disabled={!assetMultiSelectManager.selectionActive}
          onclick={() => assetMultiSelectManager.clear()}
        >
          {$t('unselect_all')}
        </Button>
      {/if}
      <Button
        leadingIcon={mdiMapMarkerMultipleOutline}
        size="small"
        color="primary"
        shape="round"
        disabled={assetMultiSelectManager.selectedAssets.length === 0}
        onclick={async () =>
          await handleUpdate().then(() => {
            timelineManager.refreshLayout();
          })}
      >
        <Text class="hidden sm:inline-block">
          {$t('apply_count', { values: { count: assetMultiSelectManager.selectedAssets.length } })}
        </Text>
      </Button>
    </div>
  {/snippet}

  {#if isLoading}
    <div class="h-full w-full flex items-center justify-center">
      <LoadingSpinner size="giant" />
    </div>
  {/if}

  <Timeline
    isSelectionMode={true}
    enableRouting={true}
    bind:timelineManager
    {options}
    assetInteraction={assetMultiSelectManager}
    removeAction={AssetAction.ARCHIVE}
    onEscape={handleEscape}
    withStacked
    onThumbnailClick={handleThumbnailClick}
  >
    {#snippet customThumbnailLayout(asset: TimelineAsset)}
      {#if hasGps(asset)}
        <div
          class="absolute bottom-1 end-3 px-4 py-1 rounded-xl text-xs transition-colors bg-immich-dark-success text-black"
        >
          {asset.city || $t('gps')}
        </div>
      {:else}
        <div
          class="absolute bottom-1 end-3 px-4 py-1 rounded-xl text-xs transition-colors bg-immich-dark-danger text-black"
        >
          {$t('gps_missing')}
        </div>
      {/if}
    {/snippet}
    {#snippet empty()}
      <EmptyPlaceholder text={$t('no_location_assets')} src={empty5Url} />
    {/snippet}
  </Timeline>
</UserPageLayout>
