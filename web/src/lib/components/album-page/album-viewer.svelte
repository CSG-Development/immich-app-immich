<script lang="ts">
  import { goto } from '$app/navigation';
  import { resolve } from '$app/paths';
  import { shortcut } from '$lib/actions/shortcut';
  import CastButton from '$lib/cast/cast-button.svelte';
  import AlbumMap from '$lib/components/album-page/album-map.svelte';
  import DownloadAction from '$lib/components/timeline/actions/DownloadAction.svelte';
  import SelectAllAssets from '$lib/components/timeline/actions/SelectAllAction.svelte';
  import AssetSelectControlBar from '$lib/components/timeline/AssetSelectControlBar.svelte';
  import Timeline from '$lib/components/timeline/Timeline.svelte';
  import { AppRoute } from '$lib/constants';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { AssetInteraction } from '$lib/stores/asset-interaction.svelte';
  import { assetViewingStore } from '$lib/stores/asset-viewing.store';
  import { featureFlags } from '$lib/stores/server-config.store';
  import { SlideshowNavigation, SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
  import { getFirstSlideshowAsset, handlePromiseError, toDate } from '$lib/utils';
  import { cancelMultiselect, downloadAlbum } from '$lib/utils/asset-utils';
  import { openFileUploadDialog } from '$lib/utils/file-uploader';
  import type { AlbumResponseDto, SharedLinkResponseDto, UserResponseDto } from '@immich/sdk';
  import { IconButton } from '@immich/ui';
  import { mdiArrowLeft, mdiDownload, mdiFileImagePlusOutline, mdiPresentationPlay } from '@mdi/js';
  import { onDestroy } from 'svelte';
  import { t } from 'svelte-i18n';
  import { get } from 'svelte/store';
  import ControlAppBar from '../shared-components/control-app-bar.svelte';
  import ThemeButton from '../shared-components/theme-button.svelte';
  import AlbumSummary from './album-summary.svelte';

  interface Props {
    sharedLink: SharedLinkResponseDto;
    user?: UserResponseDto | undefined;
  }

  let { sharedLink, user = undefined }: Props = $props();

  const album = sharedLink.album as AlbumResponseDto;

  let { isViewing: showAssetViewer, setAssetId } = assetViewingStore;
  let { slideshowState, slideshowNavigation } = slideshowStore;

  let timelineManager = new TimelineManager();
  $effect(() => void timelineManager.updateOptions({ albumId: album.id, order: album.order }));
  onDestroy(() => timelineManager.destroy());

  const assetInteraction = new AssetInteraction();

  /* dragAndDropFilesStore.subscribe((value) => {
    if (value.isDragging && value.files.length > 0) {
      handlePromiseError(fileUploadHandler({ files: value.files, albumId: album.id }));
      dragAndDropFilesStore.set({ isDragging: false, files: [] });
    }
  }); */

  let shuffledSelectedAssets: TimelineAsset[] = $derived([]);

  const handleStartSlideshow = async () => {
    assetInteraction.selectedAssets.sort(
      (a, b) => toDate(b.fileCreatedAt).getTime() - toDate(a.fileCreatedAt).getTime(),
    );
    shuffledSelectedAssets = [...assetInteraction.selectedAssets].sort(() => Math.random() - 0.5);
    const nav = get(slideshowNavigation);

    const firstAsset =
      nav === SlideshowNavigation.Shuffle
        ? await timelineManager.getRandomAsset()
        : nav === SlideshowNavigation.AscendingOrder
          ? timelineManager.months.at(-1)?.dayGroups.at(-1)?.viewerAssets.at(-1)?.asset
          : timelineManager.months[0]?.dayGroups[0]?.viewerAssets[0]?.asset;
    const firstSelectedAsset = getFirstSlideshowAsset(assetInteraction.selectedAssets, shuffledSelectedAssets, nav);

    const asset = assetInteraction.selectedAssets.length > 0 ? firstSelectedAsset : firstAsset;

    if (asset) {
      handlePromiseError(setAssetId(asset.id).then(() => ($slideshowState = SlideshowState.PlaySlideshow)));
    }
  };
</script>

<svelte:document
  use:shortcut={{
    shortcut: { key: 'Escape' },
    onShortcut: () => {
      if (!$showAssetViewer && assetInteraction.selectionActive) {
        cancelMultiselect(assetInteraction);
      }
    },
  }}
/>

<main class="relative h-dvh overflow-hidden px-3 md:px-6">
  <Timeline
    enableRouting={true}
    {album}
    {timelineManager}
    {assetInteraction}
    selectedAssets={assetInteraction.selectedAssets}
    {shuffledSelectedAssets}
  >
    <section class="pt-18 md:pt-24 px-2 md:px-0">
      <!-- ALBUM TITLE -->
      <h1 class="text-[34px] text-immich-primary outline-none transition-all dark:text-immich-dark-primary">
        {album.albumName}
      </h1>

      {#if album.assetCount > 0}
        <AlbumSummary {album} />
      {/if}

      <!-- ALBUM DESCRIPTION -->
      {#if album.description}
        <p class="whitespace-pre-line mt-3 w-full text-start font-medium text-base text-black dark:text-gray-300">
          {album.description}
        </p>
      {/if}
    </section>
  </Timeline>
</main>

<header>
  {#if assetInteraction.selectionActive}
    <AssetSelectControlBar
      ownerId={user?.id}
      assets={assetInteraction.selectedAssets}
      clearSelect={() => assetInteraction.clearMultiselect()}
    >
      <SelectAllAssets {timelineManager} {assetInteraction} />
      {#if assetInteraction.selectedAssets.length > 1}
        <IconButton
          shape="round"
          variant="ghost"
          color="secondary"
          aria-label={$t('slideshow')}
          onclick={handleStartSlideshow}
          icon={mdiPresentationPlay}
        />
      {/if}
      {#if sharedLink.allowDownload}
        <DownloadAction filename="{album.albumName}.zip" />
      {/if}
    </AssetSelectControlBar>
  {:else}
    <ControlAppBar
      showBackButton
      backIcon={mdiArrowLeft}
      onClose={async () => {
        await goto(resolve(AppRoute.SHARED_LINKS));
      }}
    >
      {#snippet trailing()}
        <CastButton />

        {#if sharedLink.allowUpload}
          <IconButton
            shape="round"
            color="secondary"
            variant="ghost"
            aria-label={$t('add_photos')}
            onclick={() => openFileUploadDialog({ albumId: album.id })}
            icon={mdiFileImagePlusOutline}
          />
        {/if}

        {#if album.assetCount > 0 && sharedLink.allowDownload}
          <IconButton
            shape="round"
            variant="ghost"
            color="secondary"
            aria-label={$t('slideshow')}
            onclick={handleStartSlideshow}
            icon={mdiPresentationPlay}
          />
          <IconButton
            shape="round"
            color="secondary"
            variant="ghost"
            aria-label={$t('download')}
            onclick={() => downloadAlbum(album)}
            icon={mdiDownload}
          />
        {/if}
        {#if sharedLink.showMetadata && $featureFlags.loaded && $featureFlags.map}
          <AlbumMap {album} />
        {/if}
        <ThemeButton />
      {/snippet}
    </ControlAppBar>
  {/if}
</header>
