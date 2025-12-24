<script lang="ts">
  import { beforeNavigate } from '$app/navigation';
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import MemoryLane from '$lib/components/photos-page/memory-lane.svelte';
  import ButtonContextMenu from '$lib/components/shared-components/context-menu/button-context-menu.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/empty-placeholder.svelte';
  import AddToAlbum from '$lib/components/timeline/actions/AddToAlbumAction.svelte';
  import ArchiveAction from '$lib/components/timeline/actions/ArchiveAction.svelte';
  import AssetJobActions from '$lib/components/timeline/actions/AssetJobActions.svelte';
  import ChangeDate from '$lib/components/timeline/actions/ChangeDateAction.svelte';
  import ChangeDescription from '$lib/components/timeline/actions/ChangeDescriptionAction.svelte';
  import ChangeLocation from '$lib/components/timeline/actions/ChangeLocationAction.svelte';
  import CreateSharedLink from '$lib/components/timeline/actions/CreateSharedLinkAction.svelte';
  import DeleteAssets from '$lib/components/timeline/actions/DeleteAssetsAction.svelte';
  import DownloadAction from '$lib/components/timeline/actions/DownloadAction.svelte';
  import FavoriteAction from '$lib/components/timeline/actions/FavoriteAction.svelte';
  import LinkLivePhotoAction from '$lib/components/timeline/actions/LinkLivePhotoAction.svelte';
  import SelectAllAssets from '$lib/components/timeline/actions/SelectAllAction.svelte';
  import SetVisibilityAction from '$lib/components/timeline/actions/SetVisibilityAction.svelte';
  import StackAction from '$lib/components/timeline/actions/StackAction.svelte';
  import TagAction from '$lib/components/timeline/actions/TagAction.svelte';
  import AssetSelectControlBar from '$lib/components/timeline/AssetSelectControlBar.svelte';
  import Timeline from '$lib/components/timeline/Timeline.svelte';
  import { AssetAction } from '$lib/constants';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import { AssetInteraction } from '$lib/stores/asset-interaction.svelte';
  import { assetViewingStore } from '$lib/stores/asset-viewing.store';
  import { isFaceEditMode } from '$lib/stores/face-edit.svelte';
  import { preferences, user } from '$lib/stores/user.store';
  import {
    updateStackedAssetInTimeline,
    updateUnstackedAssetInTimeline,
    type OnLink,
    type OnUnlink,
  } from '$lib/utils/actions';
  import { fileUploadHandler, openFileUploadDialog } from '$lib/utils/file-uploader';
  import { AssetVisibility, getAssetInfo } from '@immich/sdk';

  import MenuOption from '$lib/components/shared-components/context-menu/menu-option.svelte';
  import {
    notificationController,
    NotificationType,
  } from '$lib/components/shared-components/notification/notification';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import { SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
  import { getAssetOriginalUrl, getFirstSlideshowAsset, handlePromiseError, toDate } from '$lib/utils';
  import { canvasToBlob, getFileExtension, isWebCompatibleAsset, makeImageUnique } from '$lib/utils/asset-utils';
  import { handleError } from '$lib/utils/handle-error';
  import { IconButton } from '@immich/ui';
  import { mdiContentDuplicate, mdiDotsVertical, mdiPlus, mdiPresentationPlay } from '@mdi/js';
  import { onDestroy } from 'svelte';
  import { t } from 'svelte-i18n';
  import { get } from 'svelte/store';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  let { isViewing: showAssetViewer, setAssetId } = assetViewingStore;
  const timelineManager = new TimelineManager();
  void timelineManager.updateOptions({ visibility: AssetVisibility.Timeline, withStacked: true, withPartners: true });
  onDestroy(() => timelineManager.destroy());

  const assetInteraction = new AssetInteraction();

  let selectedAssets = $derived(assetInteraction.selectedAssets);
  let isAssetStackSelected = $derived(selectedAssets.length === 1 && !!selectedAssets[0].stack);
  let isLinkActionAvailable = $derived.by(() => {
    const isLivePhoto = selectedAssets.length === 1 && !!selectedAssets[0].livePhotoVideoId;
    const isLivePhotoCandidate =
      selectedAssets.length === 2 &&
      selectedAssets.some((asset) => asset.isImage) &&
      selectedAssets.some((asset) => asset.isVideo);

    return assetInteraction.isAllUserOwned && (isLivePhoto || isLivePhotoCandidate);
  });
  const handleEscape = () => {
    if ($showAssetViewer) {
      return;
    }
    if (assetInteraction.selectionActive) {
      assetInteraction.clearMultiselect();
      return;
    }
  };

  const handleLink: OnLink = ({ still, motion }) => {
    timelineManager.removeAssets([motion.id]);
    timelineManager.updateAssets([still]);
  };

  const handleUnlink: OnUnlink = ({ still, motion }) => {
    timelineManager.addAssets([motion]);
    timelineManager.updateAssets([still]);
  };

  const handleSetVisibility = (assetIds: string[]) => {
    timelineManager.removeAssets(assetIds);
    assetInteraction.clearMultiselect();
  };

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

  beforeNavigate(() => {
    isFaceEditMode.value = false;
  });

  const onDuplicate = async (selectedAssets: TimelineAsset[]) => {
    try {
      for (const asset of selectedAssets) {
        try {
          const assetInfo = await getAssetInfo({ id: asset.id });
          const assetType = getFileExtension(assetInfo.originalFileName);

          let blob: Blob | undefined;

          if (asset.isImage) {
            if (isWebCompatibleAsset(assetInfo)) {
              const src = getAssetOriginalUrl({ id: asset.id, cacheKey: asset.thumbhash });
              const img = new Image();
              img.src = src;
              await img.decode();

              const uniqueCanvas = makeImageUnique(img);

              blob = await canvasToBlob(uniqueCanvas);
            } else {
              notificationController.show({
                type: NotificationType.Error,
                message: $t('duplicate_error_unsupported_type', { values: { type: assetType } }),
                timeout: 3000,
              });
            }
          } else {
            notificationController.show({
              type: NotificationType.Error,
              message: $t('duplicate_error_video'),
              timeout: 3000,
            });
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
</script>

<UserPageLayout
  hideNavbar={assetInteraction.selectionActive}
  title={data.meta.title}
  description={$t('items_count', { values: { count: timelineManager.assetCount } })}
  showUploadButton
  scrollbar={false}
>
  <Timeline
    enableRouting={true}
    {timelineManager}
    {assetInteraction}
    removeAction={AssetAction.ARCHIVE}
    onEscape={handleEscape}
    withStacked
    selectedAssets={assetInteraction.selectedAssets}
    {shuffledSelectedAssets}
  >
    {#if $preferences.memories.enabled}
      <MemoryLane />
    {/if}
    {#snippet empty()}
      <EmptyPlaceholder text={$t('no_assets_message')} onClick={() => openFileUploadDialog()} />
    {/snippet}
  </Timeline>
</UserPageLayout>

{#if assetInteraction.selectionActive}
  <AssetSelectControlBar
    ownerId={$user.id}
    assets={assetInteraction.selectedAssets}
    clearSelect={() => assetInteraction.clearMultiselect()}
  >
    <IconButton
      id="test"
      color="secondary"
      variant="ghost"
      shape="round"
      icon={mdiContentDuplicate}
      aria-label={$t('duplicate')}
      onclick={() => onDuplicate(assetInteraction.selectedAssets)}
    />
    <CreateSharedLink />
    <SelectAllAssets {timelineManager} {assetInteraction} />
    <ButtonContextMenu icon={mdiPlus} title={$t('add_to')}>
      <AddToAlbum />
      <AddToAlbum shared />
    </ButtonContextMenu>
    <FavoriteAction
      removeFavorite={assetInteraction.isAllFavorite}
      onFavorite={(ids, isFavorite) =>
        timelineManager.updateAssetOperation(ids, (asset) => {
          asset.isFavorite = isFavorite;
          return { remove: false };
        })}
    ></FavoriteAction>
    <ButtonContextMenu icon={mdiDotsVertical} title={$t('menu')}>
      {#if assetInteraction.selectedAssets.length > 1}
        <MenuOption icon={mdiPresentationPlay} text={$t('slideshow')} onClick={handleStartSlideshow} />
      {/if}
      <DownloadAction menuItem />
      {#if assetInteraction.selectedAssets.length > 1 || isAssetStackSelected}
        <StackAction
          unstack={isAssetStackSelected}
          onStack={(result) => updateStackedAssetInTimeline(timelineManager, result)}
          onUnstack={(assets) => updateUnstackedAssetInTimeline(timelineManager, assets)}
        />
      {/if}
      {#if isLinkActionAvailable}
        <LinkLivePhotoAction
          menuItem
          unlink={assetInteraction.selectedAssets.length === 1}
          onLink={handleLink}
          onUnlink={handleUnlink}
        />
      {/if}
      <ChangeDate menuItem />
      <ChangeDescription menuItem />
      <ChangeLocation menuItem />
      <ArchiveAction menuItem onArchive={(assetIds) => timelineManager.removeAssets(assetIds)} />
      {#if $preferences.tags.enabled}
        <TagAction menuItem />
      {/if}
      <DeleteAssets
        menuItem
        onAssetDelete={(assetIds) => timelineManager.removeAssets(assetIds)}
        onUndoDelete={(assets) => timelineManager.addAssets(assets)}
      />
      <SetVisibilityAction menuItem onVisibilitySet={handleSetVisibility} />
      <hr />
      <AssetJobActions />
    </ButtonContextMenu>
  </AssetSelectControlBar>
{/if}
