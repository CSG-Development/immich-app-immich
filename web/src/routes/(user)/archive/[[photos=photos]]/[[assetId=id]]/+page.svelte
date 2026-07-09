<script lang="ts">
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import ButtonContextMenu from '$lib/components/shared-components/context-menu/button-context-menu.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/empty-placeholder.svelte';
  import ArchiveAction from '$lib/components/timeline/actions/ArchiveAction.svelte';
  import CreateSharedLink from '$lib/components/timeline/actions/CreateSharedLinkAction.svelte';
  import DeleteAssets from '$lib/components/timeline/actions/DeleteAssetsAction.svelte';
  import DownloadAction from '$lib/components/timeline/actions/DownloadAction.svelte';
  import FavoriteAction from '$lib/components/timeline/actions/FavoriteAction.svelte';
  import SelectAllAssets from '$lib/components/timeline/actions/SelectAllAction.svelte';
  import AssetSelectControlBar from '$lib/components/timeline/AssetSelectControlBar.svelte';
  import Timeline from '$lib/components/timeline/Timeline.svelte';
  import { AssetAction } from '$lib/constants';

  import MenuOption from '$lib/components/shared-components/context-menu/menu-option.svelte';
  import SetVisibilityAction from '$lib/components/timeline/actions/SetVisibilityAction.svelte';
  import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
  import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { getAssetBulkActions } from '$lib/services/asset.service';
  import { SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
  import { getFirstSlideshowAsset, handlePromiseError, toDate } from '$lib/utils';
  import { AssetVisibility } from '@immich/sdk';
  import { ActionButton, CommandPaletteDefaultProvider } from '@immich/ui';
  import { mdiDotsVertical, mdiPresentationPlay } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import { get } from 'svelte/store';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();
  let timelineManager = $state<TimelineManager>() as TimelineManager;
  const options = { visibility: AssetVisibility.Archive };

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
</script>

<UserPageLayout hideNavbar={assetMultiSelectManager.selectionActive} title={data.meta.title} scrollbar={false}>
  <Timeline
    enableRouting={true}
    bind:timelineManager
    {options}
    assetInteraction={assetMultiSelectManager}
    removeAction={AssetAction.UNARCHIVE}
    onEscape={handleEscape}
    selectedAssets={assetMultiSelectManager.selectedAssets}
    {shuffledSelectedAssets}
  >
    {#snippet empty()}
      <EmptyPlaceholder text={$t('no_archived_assets_message')} class="mt-10 mx-auto" />
    {/snippet}
  </Timeline>
</UserPageLayout>

{#if assetMultiSelectManager.selectionActive}
  <AssetSelectControlBar>
    {@const Actions = getAssetBulkActions($t)}
    <CommandPaletteDefaultProvider name={$t('assets')} actions={Object.values(Actions)} />
    <ArchiveAction
      unarchive
      onArchive={(ids, visibility) => timelineManager.update(ids, (asset) => (asset.visibility = visibility))}
    />
    <CreateSharedLink />
    <SelectAllAssets {timelineManager} assetInteraction={assetMultiSelectManager} />
    <ActionButton action={Actions.AddToAlbum} />
    <FavoriteAction
      removeFavorite={assetMultiSelectManager.isAllFavorite}
      onFavorite={(ids, isFavorite) => timelineManager.update(ids, (asset) => (asset.isFavorite = isFavorite))}
    />
    <ButtonContextMenu icon={mdiDotsVertical} title={$t('menu')}>
      {#if assetMultiSelectManager.selectedAssets.length > 1}
        <MenuOption icon={mdiPresentationPlay} text={$t('slideshow')} onClick={handleStartSlideshow} />
      {/if}
      <DownloadAction menuItem />
      <SetVisibilityAction menuItem onVisibilitySet={handleSetVisibility} />
      <DeleteAssets menuItem onAssetDelete={(assetIds) => timelineManager.removeAssets(assetIds)} />
    </ButtonContextMenu>
  </AssetSelectControlBar>
{/if}
