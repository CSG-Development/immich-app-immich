<script lang="ts">
  import { goto } from '$app/navigation';
  import { shortcut } from '$lib/actions/shortcut';
  import AlbumMap from '$lib/components/album-page/album-map.svelte';
  import DownloadAction from '$lib/components/timeline/actions/DownloadAction.svelte';
  import SelectAllAssets from '$lib/components/timeline/actions/SelectAllAction.svelte';
  import AssetSelectControlBar from '$lib/components/timeline/AssetSelectControlBar.svelte';
  import Timeline from '$lib/components/timeline/Timeline.svelte';
  import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
  import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
  import { featureFlagsManager } from '$lib/managers/feature-flags-manager.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { Route } from '$lib/route';
  import { handleDownloadAlbum } from '$lib/services/album.service';
  import { getGlobalActions } from '$lib/services/app.service';
  import { dragAndDropFilesStore } from '$lib/stores/drag-and-drop-files.store';
  import { SlideshowNavigation, SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
  import { getFirstSlideshowAsset, handlePromiseError, toDate } from '$lib/utils';
  import { fileUploadHandler, openFileUploadDialog } from '$lib/utils/file-uploader';
  import type { AlbumResponseDto, SharedLinkResponseDto } from '@immich/sdk';
  import { ActionButton, IconButton } from '@immich/ui';
  import { mdiArrowLeft, mdiDownload, mdiFileImagePlusOutline, mdiPresentationPlay } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import { get } from 'svelte/store';
  import ControlAppBar from '../shared-components/control-app-bar.svelte';
  import ThemeButton from '../shared-components/theme-button.svelte';
  import AlbumSummary from './album-summary.svelte';

  interface Props {
    sharedLink: SharedLinkResponseDto;
  }

  let { sharedLink }: Props = $props();

  const album = sharedLink.album as AlbumResponseDto;

  let { slideshowState, slideshowNavigation } = slideshowStore;

  const options = $derived({ albumId: album.id, order: album.order });
  let timelineManager = $state<TimelineManager>() as TimelineManager;

  dragAndDropFilesStore.subscribe((value) => {
    if (value.isDragging && value.files.length > 0) {
      handlePromiseError(fileUploadHandler({ files: value.files, albumId: album.id }));
      dragAndDropFilesStore.set({ isDragging: false, files: [] });
    }
  });

  let shuffledSelectedAssets: TimelineAsset[] = $derived([]);

  const handleStartSlideshow = async () => {
    assetMultiSelectManager.selectedAssets.sort(
      (a, b) => toDate(b.fileCreatedAt).getTime() - toDate(a.fileCreatedAt).getTime(),
    );
    shuffledSelectedAssets = [...assetMultiSelectManager.selectedAssets].sort(() => Math.random() - 0.5);
    const nav = get(slideshowNavigation);

    const firstAsset =
      nav === SlideshowNavigation.Shuffle
        ? await timelineManager.getRandomAsset()
        : nav === SlideshowNavigation.AscendingOrder
          ? timelineManager.months.at(-1)?.timelineDays.at(-1)?.viewerAssets.at(-1)?.asset
          : timelineManager.months[0]?.timelineDays[0]?.viewerAssets[0]?.asset;
    const firstSelectedAsset = getFirstSlideshowAsset(
      assetMultiSelectManager.selectedAssets,
      shuffledSelectedAssets,
      nav,
    );

    const asset = assetMultiSelectManager.selectedGroup.size > 0 ? firstSelectedAsset : firstAsset;

    if (asset) {
      handlePromiseError(
        assetViewerManager.setAssetId(asset.id).then(() => ($slideshowState = SlideshowState.PlaySlideshow)),
      );
    }
  };

  const { Cast } = $derived(getGlobalActions($t));
</script>

<svelte:document
  use:shortcut={{
    shortcut: { key: 'Escape' },
    onShortcut: () => {
      if (!assetViewerManager.isViewing && assetMultiSelectManager.selectionActive) {
        assetMultiSelectManager.clear();
      }
    },
  }}
/>

<main class="relative h-dvh overflow-hidden px-2 md:px-6 max-md:pt-(--navbar-height-md) pt-(--navbar-height)">
  <Timeline
    enableRouting={true}
    {album}
    bind:timelineManager
    {options}
    assetInteraction={assetMultiSelectManager}
    selectedAssets={assetMultiSelectManager.selectedAssets}
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
  {#if assetMultiSelectManager.selectionActive}
    <AssetSelectControlBar>
      <SelectAllAssets {timelineManager} assetInteraction={assetMultiSelectManager} />
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
        await goto(Route.sharedLinks());
      }}
    >
      {#snippet trailing()}
        <ActionButton action={Cast} />

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
            onclick={() => handleDownloadAlbum(album)}
            icon={mdiDownload}
          />
        {/if}
        {#if sharedLink.showMetadata && featureFlagsManager.value.map}
          <AlbumMap {album} />
        {/if}
        <ThemeButton />
      {/snippet}
    </ControlAppBar>
  {/if}
</header>
