<script lang="ts">
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import ButtonContextMenu from '$lib/components/shared-components/context-menu/button-context-menu.svelte';
  import MenuOption from '$lib/components/shared-components/context-menu/menu-option.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/empty-placeholder.svelte';
  import AddToAlbum from '$lib/components/timeline/actions/AddToAlbumAction.svelte';
  import ArchiveAction from '$lib/components/timeline/actions/ArchiveAction.svelte';
  import ChangeDate from '$lib/components/timeline/actions/ChangeDateAction.svelte';
  import ChangeDescription from '$lib/components/timeline/actions/ChangeDescriptionAction.svelte';
  import ChangeLocation from '$lib/components/timeline/actions/ChangeLocationAction.svelte';
  import CreateSharedLink from '$lib/components/timeline/actions/CreateSharedLinkAction.svelte';
  import DeleteAssets from '$lib/components/timeline/actions/DeleteAssetsAction.svelte';
  import DownloadAction from '$lib/components/timeline/actions/DownloadAction.svelte';
  import FavoriteAction from '$lib/components/timeline/actions/FavoriteAction.svelte';
  import SelectAllAssets from '$lib/components/timeline/actions/SelectAllAction.svelte';
  import SetVisibilityAction from '$lib/components/timeline/actions/SetVisibilityAction.svelte';
  import TagAction from '$lib/components/timeline/actions/TagAction.svelte';
  import AssetSelectControlBar from '$lib/components/timeline/AssetSelectControlBar.svelte';
  import Timeline from '$lib/components/timeline/Timeline.svelte';
  import { AssetAction } from '$lib/constants';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { AssetInteraction } from '$lib/stores/asset-interaction.svelte';
  import { assetViewingStore } from '$lib/stores/asset-viewing.store';
  import { SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
  import { preferences } from '$lib/stores/user.store';
  import { getFirstSlideshowAsset, handlePromiseError, toDate } from '$lib/utils';
  import { mdiDotsVertical, mdiPlus, mdiPresentationPlay } from '@mdi/js';
  import { onDestroy } from 'svelte';
  import { t } from 'svelte-i18n';
  import { get } from 'svelte/store';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  const timelineManager = new TimelineManager();
  void timelineManager.updateOptions({ isFavorite: true, withStacked: true });
  onDestroy(() => timelineManager.destroy());

  const assetInteraction = new AssetInteraction();

  const handleEscape = () => {
    if (assetInteraction.selectionActive) {
      assetInteraction.clearMultiselect();
      return;
    }
  };

  const handleSetVisibility = (assetIds: string[]) => {
    timelineManager.removeAssets(assetIds);
    assetInteraction.clearMultiselect();
  };

  let { setAssetId } = assetViewingStore;
  let { slideshowState, slideshowNavigation } = slideshowStore;

  let shuffledSelectedAssets: TimelineAsset[] = $derived([]);

  const handleStartSlideshow = () => {
    assetInteraction.selectedAssets.sort(
      (a, b) => toDate(b.fileCreatedAt).getTime() - toDate(a.fileCreatedAt).getTime(),
    );
    shuffledSelectedAssets = [...assetInteraction.selectedAssets].sort(() => Math.random() - 0.5);
    const nav = get(slideshowNavigation);
    const asset = getFirstSlideshowAsset(assetInteraction.selectedAssets, shuffledSelectedAssets, nav);
    if (asset) {
      handlePromiseError(setAssetId(asset.id).then(() => ($slideshowState = SlideshowState.PlaySlideshow)));
    }
  };
</script>

<UserPageLayout
  hideNavbar={assetInteraction.selectionActive}
  title={data.meta.title}
  description={$t('items_count', { values: { count: timelineManager.assetCount } })}
  scrollbar={false}
>
  <Timeline
    enableRouting={true}
    withStacked={true}
    {timelineManager}
    {assetInteraction}
    removeAction={AssetAction.UNFAVORITE}
    onEscape={handleEscape}
    selectedAssets={assetInteraction.selectedAssets}
    {shuffledSelectedAssets}
  >
    {#snippet empty()}
      <EmptyPlaceholder text={$t('no_favorites_message')} />
    {/snippet}
  </Timeline>
</UserPageLayout>

<!-- Multiselection mode app bar -->
{#if assetInteraction.selectionActive}
  <AssetSelectControlBar
    assets={assetInteraction.selectedAssets}
    clearSelect={() => assetInteraction.clearMultiselect()}
  >
    <FavoriteAction removeFavorite onFavorite={(assetIds) => timelineManager.removeAssets(assetIds)} />
    <CreateSharedLink />
    <SelectAllAssets {timelineManager} {assetInteraction} />
    <ButtonContextMenu icon={mdiPlus} title={$t('add_to')}>
      <AddToAlbum />
      <AddToAlbum shared />
    </ButtonContextMenu>
    <ButtonContextMenu icon={mdiDotsVertical} title={$t('menu')}>
      {#if assetInteraction.selectedAssets.length > 1}
        <MenuOption icon={mdiPresentationPlay} text={$t('slideshow')} onClick={handleStartSlideshow} />
      {/if}
      <DownloadAction menuItem />
      <ChangeDate menuItem />
      <ChangeDescription menuItem />
      <ChangeLocation menuItem />
      <ArchiveAction
        menuItem
        unarchive={assetInteraction.isAllArchived}
        onArchive={(assetIds) => timelineManager.removeAssets(assetIds)}
      />
      {#if $preferences.tags.enabled}
        <TagAction menuItem />
      {/if}
      <SetVisibilityAction menuItem onVisibilitySet={handleSetVisibility} />
      <DeleteAssets
        menuItem
        onAssetDelete={(assetIds) => timelineManager.removeAssets(assetIds)}
        onUndoDelete={(assets) => timelineManager.addAssets(assets)}
      />
    </ButtonContextMenu>
  </AssetSelectControlBar>
{/if}
