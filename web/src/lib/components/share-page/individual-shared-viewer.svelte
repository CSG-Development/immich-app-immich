<script lang="ts">
  import { goto } from '$app/navigation';
  import { resolve } from '$app/paths';
  import type { Action } from '$lib/components/asset-viewer/actions/action';
  import DownloadAction from '$lib/components/timeline/actions/DownloadAction.svelte';
  import RemoveFromSharedLink from '$lib/components/timeline/actions/RemoveFromSharedLinkAction.svelte';
  import AssetSelectControlBar from '$lib/components/timeline/AssetSelectControlBar.svelte';
  import { AppRoute, AssetAction } from '$lib/constants';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import type { Viewport } from '$lib/managers/timeline-manager/types';
  import { AssetInteraction } from '$lib/stores/asset-interaction.svelte';
  import { isSelectingAllAssets } from '$lib/stores/assets-store.svelte';
  import { cancelMultiselect, downloadArchive } from '$lib/utils/asset-utils';
  import { fileUploadHandler, openFileUploadDialog } from '$lib/utils/file-uploader';
  import { handleError } from '$lib/utils/handle-error';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import { addSharedLinkAssets, getAssetInfo, type SharedLinkResponseDto } from '@immich/sdk';
  import { IconButton } from '@immich/ui';
  import { mdiArrowLeft, mdiDownload, mdiFileImagePlusOutline, mdiSelectAll, mdiSelectRemove } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import AssetViewer from '../asset-viewer/asset-viewer.svelte';
  import ControlAppBar from '../shared-components/control-app-bar.svelte';
  import GalleryViewer from '../shared-components/gallery-viewer/gallery-viewer.svelte';
  import { NotificationType, notificationController } from '../shared-components/notification/notification';

  interface Props {
    sharedLink: SharedLinkResponseDto;
    isOwned: boolean;
  }

  let { sharedLink = $bindable(), isOwned }: Props = $props();

  const viewport: Viewport = $state({ width: 0, height: 0 });
  const assetInteraction = new AssetInteraction();

  let assets = $derived(sharedLink.assets.map((a) => toTimelineAsset(a)));

  /* dragAndDropFilesStore.subscribe((value) => {
    if (value.isDragging && value.files.length > 0) {
      handlePromiseError(handleUploadAssets(value.files));
      dragAndDropFilesStore.set({ isDragging: false, files: [] });
    }
  }); */

  const downloadAssets = async () => {
    await downloadArchive(`immich-shared.zip`, { assetIds: assets.map((asset) => asset.id) });
  };

  const handleUploadAssets = async (files: File[] = []) => {
    try {
      let results: (string | undefined)[] = [];
      results = await (!files || files.length === 0 || !Array.isArray(files)
        ? openFileUploadDialog()
        : fileUploadHandler({ files }));
      const data = await addSharedLinkAssets({
        ...authManager.params,
        id: sharedLink.id,
        assetIdsDto: {
          assetIds: results.filter((id) => !!id) as string[],
        },
      });

      const added = data.filter((item) => item.success).length;

      notificationController.show({
        message: $t('assets_added_count', { values: { count: added } }),
        type: NotificationType.Success,
      });
    } catch (error) {
      handleError(error, $t('errors.unable_to_add_assets_to_shared_link'));
    }
  };

  const handleSelectAll = () => {
    assetInteraction.selectAssets(assets);
  };

  const handleCancel = () => {
    cancelMultiselect(assetInteraction);
  };

  const handleAction = async (action: Action) => {
    switch (action.type) {
      case AssetAction.ARCHIVE:
      case AssetAction.DELETE:
      case AssetAction.TRASH: {
        await goto(resolve(AppRoute.PHOTOS));
        break;
      }
    }
  };

  $effect(() => {
    if (assets.length == assetInteraction.selectedAssets.length) {
      isSelectingAllAssets.set(true);
    } else {
      isSelectingAllAssets.set(false);
    }
  });
</script>

<section>
  {#if sharedLink?.allowUpload || assets.length > 1}
    {#if assetInteraction.selectionActive}
      <AssetSelectControlBar assets={assetInteraction.selectedAssets} clearSelect={handleCancel}>
        <IconButton
          shape="round"
          color="secondary"
          variant="ghost"
          aria-label={$isSelectingAllAssets ? $t('unselect_all') : $t('select_all')}
          icon={$isSelectingAllAssets ? mdiSelectRemove : mdiSelectAll}
          onclick={$isSelectingAllAssets ? handleCancel : handleSelectAll}
        />
        {#if sharedLink?.allowDownload}
          <DownloadAction filename="immich-shared.zip" />
        {/if}
        {#if isOwned}
          <RemoveFromSharedLink bind:sharedLink />
        {/if}
      </AssetSelectControlBar>
    {:else}
      <ControlAppBar
        backIcon={mdiArrowLeft}
        onClose={async () => {
          await goto(resolve(AppRoute.SHARED_LINKS));
        }}
      >
        {#snippet trailing()}
          {#if sharedLink?.allowUpload}
            <IconButton
              shape="round"
              color="secondary"
              variant="ghost"
              aria-label={$t('add_photos')}
              onclick={() => handleUploadAssets()}
              icon={mdiFileImagePlusOutline}
            />
          {/if}

          {#if sharedLink?.allowDownload}
            <IconButton
              shape="round"
              color="secondary"
              variant="ghost"
              aria-label={$t('download')}
              onclick={downloadAssets}
              icon={mdiDownload}
            />
          {/if}
        {/snippet}
      </ControlAppBar>
    {/if}
    <section
      class="mt-[82px] md:mt-[114px] mx-3 md:mx-6"
      bind:clientHeight={viewport.height}
      bind:clientWidth={viewport.width}
    >
      <GalleryViewer {assets} {assetInteraction} {viewport} />
    </section>
  {:else if assets.length === 1}
    {#await getAssetInfo({ ...authManager.params, id: assets[0].id }) then asset}
      <AssetViewer
        {asset}
        showCloseButton={false}
        onAction={handleAction}
        onPrevious={() => Promise.resolve(false)}
        onNext={() => Promise.resolve(false)}
        onRandom={() => Promise.resolve(undefined)}
        onClose={() => {}}
        {assetInteraction}
      />
    {/await}
  {/if}
</section>
