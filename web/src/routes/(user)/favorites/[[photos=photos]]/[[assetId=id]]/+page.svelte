<script lang="ts">
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/empty-placeholder.svelte';
  import CreateSharedLink from '$lib/components/timeline/actions/CreateSharedLinkAction.svelte';
  import FavoriteAction from '$lib/components/timeline/actions/FavoriteAction.svelte';
  import SelectAllAssets from '$lib/components/timeline/actions/SelectAllAction.svelte';
  import AssetSelectControlBar from '$lib/components/timeline/AssetSelectControlBar.svelte';
  import Timeline from '$lib/components/timeline/Timeline.svelte';
  import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
  import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { getAssetBulkActions } from '$lib/services/asset.service';
  import { getAssetSelectMenuItems } from '$lib/services/asset-select-menu.service';
  import { SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
  import { getFirstSlideshowAsset, handlePromiseError, toDate } from '$lib/utils';
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
  const options = { isFavorite: true, withStacked: true };

  const handleEscape = () => {
    if (assetMultiSelectManager.selectionActive) {
      assetMultiSelectManager.clear();
      return;
    }
  };

  const handleSetVisibility = (assetIds: string[]) => {
    timelineManager.removeAssets(assetIds);
    assetMultiSelectManager.clear();
  };

  let { slideshowState, slideshowNavigation } = slideshowStore;

  let shuffledSelectedAssets: TimelineAsset[] = $derived([]);

  const handleStartSlideshow = () => {
    assetMultiSelectManager.selectedAssets.sort(
      (a, b) => toDate(b.fileCreatedAt).getTime() - toDate(a.fileCreatedAt).getTime(),
    );
    shuffledSelectedAssets = [...assetMultiSelectManager.selectedAssets].sort(() => Math.random() - 0.5);
    const nav = get(slideshowNavigation);
    const asset = getFirstSlideshowAsset(assetMultiSelectManager.selectedAssets, shuffledSelectedAssets, nav);
    if (asset) {
      handlePromiseError(
        assetViewerManager.setAssetId(asset.id).then(() => ($slideshowState = SlideshowState.PlaySlideshow)),
      );
    }
  };

  const menuItems = $derived(
    getAssetSelectMenuItems($t, {
      showSlideshow: true,
      onStartSlideshow: handleStartSlideshow,
      unarchive: assetMultiSelectManager.isAllArchived,
      onArchive: (ids, visibility) => timelineManager.update(ids, (asset) => (asset.visibility = visibility)),
      onVisibilitySet: handleSetVisibility,
      onAssetDelete: (assetIds) => timelineManager.removeAssets(assetIds),
      onUndoDelete: (assets) => timelineManager.upsertAssets(assets),
    }),
  );
</script>

<UserPageLayout hideNavbar={assetMultiSelectManager.selectionActive} title={data.meta.title} scrollbar={false}>
  <Timeline
    enableRouting={true}
    withStacked={true}
    bind:timelineManager
    {options}
    assetInteraction={assetMultiSelectManager}
    onEscape={handleEscape}
    selectedAssets={assetMultiSelectManager.selectedAssets}
    {shuffledSelectedAssets}
  >
    {#snippet empty()}
      <EmptyPlaceholder text={$t('no_favorites_message')} />
    {/snippet}
  </Timeline>
</UserPageLayout>

{#if assetMultiSelectManager.selectionActive}
  <AssetSelectControlBar>
    {@const Actions = getAssetBulkActions($t)}
    <CommandPaletteDefaultProvider name={$t('assets')} actions={Object.values(Actions)} />
    <FavoriteAction removeFavorite onFavorite={(assetIds) => timelineManager.removeAssets(assetIds)} />
    <CreateSharedLink />
    <SelectAllAssets {timelineManager} assetInteraction={assetMultiSelectManager} />
    <ActionButton action={Actions.AddToAlbum} />
    <ContextMenuButton icon={mdiDotsVertical} aria-label={$t('menu')} items={menuItems} />
  </AssetSelectControlBar>
{/if}
