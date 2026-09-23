<script lang="ts">
  import type { SelectionBBox } from '$lib/components/shared-components/map/types';
  import CreateSharedLink from '$lib/components/timeline/actions/CreateSharedLinkAction.svelte';
  import DownloadAction from '$lib/components/timeline/actions/DownloadAction.svelte';
  import FavoriteAction from '$lib/components/timeline/actions/FavoriteAction.svelte';
  import SelectAllAssets from '$lib/components/timeline/actions/SelectAllAction.svelte';
  import AssetSelectControlBar from '$lib/components/timeline/AssetSelectControlBar.svelte';
  import Timeline from '$lib/components/timeline/Timeline.svelte';
  import Portal from '$lib/elements/Portal.svelte';
  import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import { getAssetBulkActions } from '$lib/services/asset.service';
  import { getAssetSelectMenuItems } from '$lib/services/asset-select-menu.service';
  import { mapSettings } from '$lib/stores/preferences.store';
  import {
    updateStackedAssetInTimeline,
    updateUnstackedAssetInTimeline,
    type OnLink,
    type OnUnlink,
  } from '$lib/utils/actions';
  import { AssetVisibility } from '@immich/sdk';
  import { ActionButton, CloseButton, CommandPaletteDefaultProvider, ContextMenuButton, Icon } from '@immich/ui';
  import { mdiDotsVertical, mdiImageMultiple } from '@mdi/js';
  import { ceil, floor } from 'lodash-es';
  import { t } from 'svelte-i18n';

  interface Props {
    bbox: SelectionBBox;
    selectedClusterIds: Set<string>;
    assetCount: number;
    onClose: () => void;
  }

  let { bbox, selectedClusterIds, assetCount, onClose }: Props = $props();

  let timelineManager = $state<TimelineManager>() as TimelineManager;
  let selectedAssets = $derived(assetMultiSelectManager.assets);
  let isAssetStackSelected = $derived(selectedAssets.length === 1 && !!selectedAssets[0].stack);
  let isLinkActionAvailable = $derived.by(() => {
    const isLivePhoto = selectedAssets.length === 1 && !!selectedAssets[0].livePhotoVideoId;
    const isLivePhotoCandidate =
      selectedAssets.length === 2 &&
      selectedAssets.some((asset) => asset.isImage) &&
      selectedAssets.some((asset) => asset.isVideo);

    return assetMultiSelectManager.isAllUserOwned && (isLivePhoto || isLivePhotoCandidate);
  });

  const handleLink: OnLink = ({ still, motion }) => {
    timelineManager.removeAssets([motion.id]);
    timelineManager.upsertAssets([still]);
  };

  const handleUnlink: OnUnlink = ({ still, motion }) => {
    timelineManager.upsertAssets([motion]);
    timelineManager.upsertAssets([still]);
  };

  const handleSetVisibility = (assetIds: string[]) => {
    timelineManager.removeAssets(assetIds);
    assetMultiSelectManager.clear();
  };

  const handleEscape = () => {
    assetMultiSelectManager.clear();
  };

  const timelineBoundingBox = $derived(
    `${floor(bbox.west, 6)},${floor(bbox.south, 6)},${ceil(bbox.east, 6)},${ceil(bbox.north, 6)}`,
  );

  const timelineOptions = $derived({
    bbox: timelineBoundingBox,
    visibility: $mapSettings.includeArchived ? undefined : AssetVisibility.Timeline,
    isFavorite: $mapSettings.onlyFavorites || undefined,
    withPartners: $mapSettings.withPartners || undefined,
    assetFilter: selectedClusterIds,
  });

  $effect.pre(() => {
    void timelineOptions;
    assetMultiSelectManager.clear();
  });

  const menuItems = $derived(
    getAssetSelectMenuItems($t, {
      showStack: assetMultiSelectManager.assets.length > 1 || isAssetStackSelected,
      onStack: (result) => updateStackedAssetInTimeline(timelineManager, result),
      onUnstack: (assets) => updateUnstackedAssetInTimeline(timelineManager, assets),
      showLinkLivePhoto: isLinkActionAvailable,
      onLink: handleLink,
      onUnlink: handleUnlink,
      unarchive: assetMultiSelectManager.isAllArchived,
      onArchive: (ids, visibility) => timelineManager.update(ids, (asset) => (asset.visibility = visibility)),
      onVisibilitySet: handleSetVisibility,
      onAssetDelete: (assetIds) => timelineManager.removeAssets(assetIds),
      onUndoDelete: (assets) => timelineManager.upsertAssets(assets),
      showJobs: true,
    }),
  );
</script>

<aside class="flex h-full w-full flex-col contain-content overflow-hidden bg-immich-bg p-2 dark:bg-immich-dark-bg">
  <div class="-mx-2 flex items-center justify-between border-b border-gray-200 px-2 pb-2 dark:border-immich-dark-gray">
    <div class="flex items-center gap-2">
      <Icon icon={mdiImageMultiple} size="20" />
      <p class="text-sm font-medium text-immich-fg dark:text-immich-dark-fg">
        {$t('assets_count', { values: { count: assetCount } })}
      </p>
    </div>
    <CloseButton onclick={onClose} />
  </div>

  <div class="min-h-0 flex-1 pt-2">
    <Timeline
      bind:timelineManager
      enableRouting={false}
      options={timelineOptions}
      onEscape={handleEscape}
      assetInteraction={assetMultiSelectManager}
      showArchiveIcon
    />
  </div>
</aside>

{#if assetMultiSelectManager.selectionActive}
  {@const Actions = getAssetBulkActions($t)}
  <CommandPaletteDefaultProvider name={$t('assets')} actions={Object.values(Actions)} />

  <Portal target="body">
    <AssetSelectControlBar>
      <CreateSharedLink />
      <SelectAllAssets {timelineManager} assetInteraction={assetMultiSelectManager} />
      <ActionButton action={Actions.AddToAlbum} />

      {#if assetMultiSelectManager.isAllUserOwned}
        <FavoriteAction
          removeFavorite={assetMultiSelectManager.isAllFavorite}
          onFavorite={(ids, isFavorite) => timelineManager.update(ids, (asset) => (asset.isFavorite = isFavorite))}
        />

        <ContextMenuButton icon={mdiDotsVertical} aria-label={$t('menu')} items={menuItems} />
      {:else}
        <DownloadAction />
      {/if}
    </AssetSelectControlBar>
  </Portal>
{/if}
