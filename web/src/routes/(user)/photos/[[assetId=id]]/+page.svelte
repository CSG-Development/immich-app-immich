<script lang="ts">
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/empty-placeholder.svelte';
  import CreateSharedLink from '$lib/components/timeline/actions/CreateSharedLinkAction.svelte';
  import DownloadAction from '$lib/components/timeline/actions/DownloadAction.svelte';
  import FavoriteAction from '$lib/components/timeline/actions/FavoriteAction.svelte';
  import SelectAllAssets from '$lib/components/timeline/actions/SelectAllAction.svelte';
  import AssetSelectControlBar from '$lib/components/timeline/AssetSelectControlBar.svelte';
  import Timeline from '$lib/components/timeline/Timeline.svelte';
  import { AssetAction } from '$lib/constants';
  import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
  import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
  import { memoryManager } from '$lib/managers/memory-manager.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { Route } from '$lib/route';
  import { getAssetBulkActions } from '$lib/services/asset.service';
  import { getAssetSelectMenuItems } from '$lib/services/asset-select-menu.service';
  import { SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
  import { preferences } from '$lib/stores/user.store';
  import { locale } from '$lib/stores/preferences.store';
  import {
    getAssetMediaUrl,
    getAssetOriginalUrl,
    getFirstSlideshowAsset,
    handlePromiseError,
    memoryLaneTitle,
    toDate,
  } from '$lib/utils';
  import {
    updateStackedAssetInTimeline,
    updateUnstackedAssetInTimeline,
    type OnLink,
    type OnUnlink,
  } from '$lib/utils/actions';
  import { canvasToBlob, getFileExtension, isWebCompatibleImage, makeImageUnique } from '$lib/utils/asset-utils';
  import { fileUploadHandler, openFileUploadDialog } from '$lib/utils/file-uploader';
  import { handleError } from '$lib/utils/handle-error';
  import { formatPageTitleWithCount } from '$lib/utils/string-utils';
  import { getAltText } from '$lib/utils/thumbnail-util';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import { AssetVisibility, getAssetInfo } from '@immich/sdk';
  import {
    ActionButton,
    CommandPaletteDefaultProvider,
    ContextMenuButton,
    IconButton,
    ImageCarousel,
    toastManager,
  } from '@immich/ui';
  import { mdiContentDuplicate, mdiDotsVertical } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import { get } from 'svelte/store';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  let timelineManager = $state<TimelineManager>() as TimelineManager;
  const options = { visibility: AssetVisibility.Timeline, withStacked: true, withPartners: true };

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

  const onDuplicate = async (selectedAssets: TimelineAsset[]) => {
    try {
      for (const asset of selectedAssets) {
        try {
          const assetInfo = await getAssetInfo({ id: asset.id });
          const assetType = getFileExtension(assetInfo.originalFileName);

          let blob: Blob | undefined;

          if (asset.isImage) {
            if (isWebCompatibleImage(assetInfo)) {
              const src = getAssetOriginalUrl({ id: asset.id, cacheKey: asset.thumbhash });
              const img = new Image();
              img.src = src;
              await img.decode();

              const uniqueCanvas = makeImageUnique(img);

              blob = await canvasToBlob(uniqueCanvas);
            } else {
              toastManager.danger(
                { description: $t('duplicate_error_unsupported_type', { values: { type: assetType } }) },
                { timeout: 3000 },
              );
            }
          } else {
            toastManager.danger({ description: $t('duplicate_error_video') }, { timeout: 3000 });
          }
          if (blob) {
            const resultFile = new File([blob], assetInfo.originalFileName, { type: assetInfo.originalMimeType });
            await fileUploadHandler({ files: [resultFile] });
          }
        } catch (error) {
          handleError(error, $t('duplicate_error'));
        }
      }
    } catch (error) {
      handleError(error, $t('duplicate_error'));
    }
  };

  const items = $derived(
    memoryManager.memories.map((memory) => ({
      id: memory.id,
      title: $memoryLaneTitle(memory),
      href: Route.memories({ id: memory.assets[0].id }),
      alt: $t('memory_lane_title', { values: { title: $getAltText(toTimelineAsset(memory.assets[0])) } }),
      src: getAssetMediaUrl({ id: memory.assets[0].id }),
    })),
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
    {#if $preferences.memories.enabled}
      <ImageCarousel {items} />
    {/if}
    {#snippet empty()}
      <EmptyPlaceholder text={$t('no_assets_message')} onClick={() => openFileUploadDialog()} />
    {/snippet}
  </Timeline>
</UserPageLayout>

{#if assetMultiSelectManager.selectionActive}
  <AssetSelectControlBar>
    {@const Actions = getAssetBulkActions($t)}
    <CommandPaletteDefaultProvider name={$t('assets')} actions={Object.values(Actions)} />
    <IconButton
      color="secondary"
      variant="ghost"
      shape="round"
      icon={mdiContentDuplicate}
      aria-label={$t('duplicate')}
      onclick={() => onDuplicate(assetMultiSelectManager.selectedAssets)}
    />

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
{/if}
