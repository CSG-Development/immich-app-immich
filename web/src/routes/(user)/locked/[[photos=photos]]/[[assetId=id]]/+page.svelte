<script lang="ts">
  import { goto } from '$app/navigation';
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import OnEvents from '$lib/components/OnEvents.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/empty-placeholder.svelte';
  import SelectAllAssets from '$lib/components/timeline/actions/SelectAllAction.svelte';
  import SetVisibilityAction from '$lib/components/timeline/actions/SetVisibilityAction.svelte';
  import AssetSelectControlBar from '$lib/components/timeline/AssetSelectControlBar.svelte';
  import Timeline from '$lib/components/timeline/Timeline.svelte';
  import { AssetAction } from '$lib/constants';
  import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
  import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { Route } from '$lib/route';
  import { getAssetSelectMenuItems } from '$lib/services/asset-select-menu.service';
  import { getUserActions } from '$lib/services/user.service';
  import { SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
  import { getFirstSlideshowAsset, handlePromiseError, toDate } from '$lib/utils';
  import { AssetVisibility } from '@immich/sdk';
  import { ContextMenuButton } from '@immich/ui';
  import { mdiDotsVertical } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import { get } from 'svelte/store';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  let timelineManager = $state<TimelineManager>() as TimelineManager;
  const options = { visibility: AssetVisibility.Locked };

  const handleEscape = () => {
    if (assetMultiSelectManager.selectionActive) {
      assetMultiSelectManager.clear();
      return;
    }
  };

  const handleMoveOffLockedFolder = (assetIds: string[]) => {
    assetMultiSelectManager.clear();
    timelineManager.removeAssets(assetIds);
  };

  const { LockSession } = $derived(getUserActions($t));

  const onSessionLocked = async () => {
    await goto(Route.photos());
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
      showChangeDescription: false,
      showArchive: false,
      showTag: false,
      showVisibility: false,
      forceDelete: true,
      onAssetDelete: (assetIds) => timelineManager.removeAssets(assetIds),
    }),
  );
</script>

<OnEvents {onSessionLocked} />

<UserPageLayout
  title={data.meta.title}
  actions={[LockSession]}
  hideNavbar={assetMultiSelectManager.selectionActive}
  scrollbar={false}
>
  <Timeline
    enableRouting={true}
    bind:timelineManager
    {options}
    assetInteraction={assetMultiSelectManager}
    onEscape={handleEscape}
    removeAction={AssetAction.SET_VISIBILITY_TIMELINE}
    selectedAssets={assetMultiSelectManager.selectedAssets}
    {shuffledSelectedAssets}
  >
    {#snippet empty()}
      <EmptyPlaceholder text={$t('no_locked_photos_message')} />
    {/snippet}
  </Timeline>
</UserPageLayout>

<!-- Multi-selection mode app bar -->
{#if assetMultiSelectManager.selectionActive}
  <AssetSelectControlBar>
    <SelectAllAssets withText {timelineManager} assetInteraction={assetMultiSelectManager} />
    <SetVisibilityAction unlock onVisibilitySet={handleMoveOffLockedFolder} />
    <ContextMenuButton icon={mdiDotsVertical} aria-label={$t('menu')} items={menuItems} />
  </AssetSelectControlBar>
{/if}
