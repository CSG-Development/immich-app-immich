<script lang="ts">
  import { goto } from '$app/navigation';
  import { resolve } from '$app/paths';
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import ButtonContextMenu from '$lib/components/shared-components/context-menu/button-context-menu.svelte';
  import MenuOption from '$lib/components/shared-components/context-menu/menu-option.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/empty-placeholder.svelte';
  import ChangeDate from '$lib/components/timeline/actions/ChangeDateAction.svelte';
  import ChangeLocation from '$lib/components/timeline/actions/ChangeLocationAction.svelte';
  import DeleteAssets from '$lib/components/timeline/actions/DeleteAssetsAction.svelte';
  import DownloadAction from '$lib/components/timeline/actions/DownloadAction.svelte';
  import SelectAllAssets from '$lib/components/timeline/actions/SelectAllAction.svelte';
  import SetVisibilityAction from '$lib/components/timeline/actions/SetVisibilityAction.svelte';
  import AssetSelectControlBar from '$lib/components/timeline/AssetSelectControlBar.svelte';
  import Timeline from '$lib/components/timeline/Timeline.svelte';
  import { AppRoute, AssetAction } from '$lib/constants';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { AssetInteraction } from '$lib/stores/asset-interaction.svelte';
  import { assetViewingStore } from '$lib/stores/asset-viewing.store';
  import { SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
  import { getFirstSlideshowAsset, handlePromiseError, toDate } from '$lib/utils';
  import { AssetVisibility, lockAuthSession } from '@immich/sdk';
  import { Button } from '@immich/ui';
  import { mdiDotsVertical, mdiLockOutline, mdiPresentationPlay } from '@mdi/js';
  import { onDestroy } from 'svelte';
  import { t } from 'svelte-i18n';
  import { get } from 'svelte/store';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  const timelineManager = new TimelineManager();
  void timelineManager.updateOptions({ visibility: AssetVisibility.Locked });
  onDestroy(() => timelineManager.destroy());

  const assetInteraction = new AssetInteraction();

  const handleEscape = () => {
    if (assetInteraction.selectionActive) {
      assetInteraction.clearMultiselect();
      return;
    }
  };

  const handleMoveOffLockedFolder = (assetIds: string[]) => {
    assetInteraction.clearMultiselect();
    timelineManager.removeAssets(assetIds);
  };

  const handleLock = async () => {
    await lockAuthSession();
    await goto(resolve(AppRoute.PHOTOS));
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
  {#snippet buttons()}
    <Button size="small" variant="ghost" color="primary" leadingIcon={mdiLockOutline} onclick={handleLock}>
      {$t('lock')}
    </Button>
  {/snippet}

  <Timeline
    enableRouting={true}
    {timelineManager}
    {assetInteraction}
    onEscape={handleEscape}
    removeAction={AssetAction.SET_VISIBILITY_TIMELINE}
    selectedAssets={assetInteraction.selectedAssets}
    {shuffledSelectedAssets}
  >
    {#snippet empty()}
      <EmptyPlaceholder text={$t('no_locked_photos_message')} title={$t('nothing_here_yet')} />
    {/snippet}
  </Timeline>
</UserPageLayout>

<!-- Multi-selection mode app bar -->
{#if assetInteraction.selectionActive}
  <AssetSelectControlBar
    assets={assetInteraction.selectedAssets}
    clearSelect={() => assetInteraction.clearMultiselect()}
  >
    <SelectAllAssets withText {timelineManager} {assetInteraction} />
    <SetVisibilityAction unlock onVisibilitySet={handleMoveOffLockedFolder} />
    <ButtonContextMenu icon={mdiDotsVertical} title={$t('menu')}>
      {#if assetInteraction.selectedAssets.length > 1}
        <MenuOption icon={mdiPresentationPlay} text={$t('slideshow')} onClick={handleStartSlideshow} />
      {/if}
      <DownloadAction menuItem />
      <ChangeDate menuItem />
      <ChangeLocation menuItem />
      <DeleteAssets menuItem force onAssetDelete={(assetIds) => timelineManager.removeAssets(assetIds)} />
    </ButtonContextMenu>
  </AssetSelectControlBar>
{/if}
