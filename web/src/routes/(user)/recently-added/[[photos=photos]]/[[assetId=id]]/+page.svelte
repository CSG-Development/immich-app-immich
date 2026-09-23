<script lang="ts">
  import UserPageLayout from '$lib/components/layouts/UserPageLayout.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/EmptyPlaceholder.svelte';
  import CreateSharedLink from '$lib/components/timeline/actions/CreateSharedLinkAction.svelte';
  import FavoriteAction from '$lib/components/timeline/actions/FavoriteAction.svelte';
  import SelectAllAssets from '$lib/components/timeline/actions/SelectAllAction.svelte';
  import AssetSelectControlBar from '$lib/components/timeline/AssetSelectControlBar.svelte';
  import Timeline from '$lib/components/timeline/Timeline.svelte';
  import { AssetAction } from '$lib/constants';
  import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
  import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { getAssetBulkActions } from '$lib/services/asset.service';
  import { getAssetSelectMenuItems } from '$lib/services/asset-select-menu.service';
  import { locale } from '$lib/stores/preferences.store';
  import { slideshowStore } from '$lib/stores/slideshow.store';
  import {
    updateStackedAssetInTimeline,
    updateUnstackedAssetInTimeline,
    type OnLink,
    type OnUnlink,
  } from '$lib/utils/actions';
  import { openFileUploadDialog } from '$lib/utils/file-uploader';
  import { startSelectionSlideshow } from '$lib/utils/slideshow-utils';
  import { formatPageTitleWithCount } from '$lib/utils/string-utils';
  import { AssetOrderBy, AssetVisibility } from '@immich/sdk';
  import { ActionButton, CommandPaletteDefaultProvider, ContextMenuButton } from '@immich/ui';
  import { mdiDotsVertical } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import { get } from 'svelte/store';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  let timelineManager = $state<TimelineManager>() as TimelineManager;
  const options = {
    visibility: AssetVisibility.Timeline,
    withStacked: true,
    withPartners: true,
    orderBy: AssetOrderBy.CreatedAt,
  };

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

  const handleEscape = () => {
    if (assetViewerManager.isViewing) {
      return;
    }
    if (assetMultiSelectManager.selectionActive) {
      assetMultiSelectManager.clear();
      return;
    }
  };

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

  let { slideshowNavigation } = slideshowStore;
  let shuffledSelectedAssets: TimelineAsset[] = $derived([]);

  const handleStartSlideshow = async () => {
    shuffledSelectedAssets = await startSelectionSlideshow(get(slideshowNavigation));
  };

  const menuItems = $derived(
    getAssetSelectMenuItems($t, {
      showSlideshow: true,
      onStartSlideshow: handleStartSlideshow,
      showStack: assetMultiSelectManager.assets.length > 1 || isAssetStackSelected,
      onStack: (result) => updateStackedAssetInTimeline(timelineManager, result),
      onUnstack: (assets) => updateUnstackedAssetInTimeline(timelineManager, assets),
      showLinkLivePhoto: isLinkActionAvailable,
      onLink: handleLink,
      onUnlink: handleUnlink,
      onArchive: (ids, visibility) => timelineManager.update(ids, (asset) => (asset.visibility = visibility)),
      onAssetDelete: (assetIds) => timelineManager.removeAssets(assetIds),
      onUndoDelete: (assets) => timelineManager.upsertAssets(assets),
      onVisibilitySet: handleSetVisibility,
      showJobs: true,
    }),
  );
</script>

<UserPageLayout
  hideNavbar={assetMultiSelectManager.selectionActive}
  title={formatPageTitleWithCount(data.meta.title, timelineManager?.assetCount ?? 0, $locale)}
  scrollbar={false}
>
  <Timeline
    enableRouting={true}
    bind:timelineManager
    {options}
    assetInteraction={assetMultiSelectManager}
    removeAction={AssetAction.ARCHIVE}
    onEscape={handleEscape}
    withStacked
    selectedAssets={assetMultiSelectManager.selectedAssets}
    {shuffledSelectedAssets}
  >
    {#snippet empty()}
      <EmptyPlaceholder text={$t('no_assets_message')} onClick={() => openFileUploadDialog()} class="mx-auto mt-10" />
    {/snippet}
  </Timeline>
</UserPageLayout>

{#if assetMultiSelectManager.selectionActive}
  <AssetSelectControlBar>
    {@const Actions = getAssetBulkActions($t)}
    <CommandPaletteDefaultProvider name={$t('assets')} actions={Object.values(Actions)} />

    <CreateSharedLink />
    <SelectAllAssets {timelineManager} assetInteraction={assetMultiSelectManager} />
    <ActionButton action={Actions.AddToAlbum} />

    {#if assetMultiSelectManager.isAllUserOwned}
      <FavoriteAction
        removeFavorite={assetMultiSelectManager.isAllFavorite}
        onFavorite={(ids, isFavorite) => timelineManager.update(ids, (asset) => (asset.isFavorite = isFavorite))}
      />
    {/if}
    <ContextMenuButton icon={mdiDotsVertical} aria-label={$t('menu')} items={menuItems} />
  </AssetSelectControlBar>
{/if}
