<script lang="ts">
  import { goto, invalidate, onNavigate } from '$app/navigation';
  import { scrollMemoryClearer } from '$lib/actions/scroll-memory';
  import AlbumDescription from '$lib/components/album-page/album-description.svelte';
  import AlbumMap from '$lib/components/album-page/album-map.svelte';
  import AlbumSummary from '$lib/components/album-page/album-summary.svelte';
  import AlbumTitle from '$lib/components/album-page/album-title.svelte';
  import ActivityStatus from '$lib/components/asset-viewer/activity-status.svelte';
  import ActivityViewer from '$lib/components/asset-viewer/activity-viewer.svelte';
  import HeaderActionButton from '$lib/components/HeaderActionButton.svelte';
  import OnEvents from '$lib/components/OnEvents.svelte';
  import ControlAppBar from '$lib/components/shared-components/control-app-bar.svelte';
  import UserAvatar from '$lib/components/shared-components/user-avatar.svelte';
  import CreateSharedLink from '$lib/components/timeline/actions/CreateSharedLinkAction.svelte';
  import FavoriteAction from '$lib/components/timeline/actions/FavoriteAction.svelte';
  import SelectAllAssets from '$lib/components/timeline/actions/SelectAllAction.svelte';
  import AssetSelectControlBar from '$lib/components/timeline/AssetSelectControlBar.svelte';
  import Timeline from '$lib/components/timeline/Timeline.svelte';
  import { AlbumPageViewMode } from '$lib/constants';
  import { activityManager } from '$lib/managers/activity-manager.svelte';
  import { assetMultiSelectManager, AssetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
  import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
  import { eventManager } from '$lib/managers/event-manager.svelte';
  import { featureFlagsManager } from '$lib/managers/feature-flags-manager.svelte';
  import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
  import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
  import AlbumOptionsModal from '$lib/modals/AlbumOptionsModal.svelte';
  import SharedLinkCreateModal from '$lib/modals/SharedLinkCreateModal.svelte';
  import { Route } from '$lib/route';
  import {
    getAlbumActions,
    getAlbumAssetsActions,
    handleDeleteAlbum,
    handleDownloadAlbum,
  } from '$lib/services/album.service';
  import { getGlobalActions } from '$lib/services/app.service';
  import { getAssetBulkActions } from '$lib/services/asset.service';
  import { getAssetSelectMenuItems } from '$lib/services/asset-select-menu.service';
  import { SlideshowNavigation, SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
  import { user } from '$lib/stores/user.store';
  import { getFirstSlideshowAsset, handlePromiseError, toDate } from '$lib/utils';
  import {
    albumAccessMessageKey,
    checkAlbumEditAccess,
    classifyAlbumAccessError,
    type AlbumEditAccessResult,
  } from '$lib/utils/album-access';
  import { handleError } from '$lib/utils/handle-error';
  import { navigate, type AssetGridRouteSearchParams } from '$lib/utils/navigation';
  import {
    AlbumUserRole,
    AssetVisibility,
    getAlbumInfo,
    removeAssetFromAlbum,
    updateAlbumInfo,
    type AlbumResponseDto,
  } from '@immich/sdk';
  import {
    ActionButton,
    CommandPaletteDefaultProvider,
    ContextMenuButton,
    Icon,
    IconButton,
    modalManager,
    toastManager,
    type ActionItem,
  } from '@immich/ui';
  import {
    mdiAccountEye,
    mdiAccountEyeOutline,
    mdiArrowLeft,
    mdiCogOutline,
    mdiDotsVertical,
    mdiDownload,
    mdiImageOutline,
    mdiImagePlusOutline,
    mdiImageRemoveOutline,
    mdiLink,
    mdiPlus,
    mdiPresentationPlay,
    mdiTrashCanOutline,
  } from '@mdi/js';
  import { onDestroy } from 'svelte';
  import { t } from 'svelte-i18n';
  import { get } from 'svelte/store';
  import { fly } from 'svelte/transition';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data = $bindable() }: Props = $props();

  let { slideshowState, slideshowNavigation } = slideshowStore;
  let oldAt: AssetGridRouteSearchParams | null | undefined = $state();

  let viewMode: AlbumPageViewMode = $state(AlbumPageViewMode.VIEW);
  let timelineManager = $state<TimelineManager>() as TimelineManager;
  let showAlbumUsers = $derived(timelineManager?.showAssetOwners ?? false);

  const timelineMultiSelectManager = new AssetMultiSelectManager();

  const notifyAlbumAccessResult = (result: Exclude<AlbumEditAccessResult, { kind: 'allowed' }>) => {
    const message = $t(albumAccessMessageKey(result));
    if (result.kind === 'view_only') {
      toastManager.warning(message);
    } else {
      toastManager.danger(message);
    }
  };

  const handleLostAlbumAccess = async (
    result: Extract<AlbumEditAccessResult, { kind: 'access_denied' | 'deleted' }>,
  ) => {
    notifyAlbumAccessResult(result);
    await goto(Route.albums());
  };

  const handleFavorite = async () => {
    try {
      await activityManager.toggleLike();
    } catch (error) {
      handleError(error, $t('errors.cant_change_asset_favorite'));
    }
  };

  const handleEscape = async () => {
    timelineManager.suspendTransitions = true;
    if (viewMode === AlbumPageViewMode.SELECT_THUMBNAIL) {
      viewMode = AlbumPageViewMode.VIEW;
      return;
    }
    if (viewMode === AlbumPageViewMode.SELECT_ASSETS) {
      await handleCloseSelectAssets();
      return;
    }
    if (assetViewerManager.isViewing) {
      return;
    }
    if (assetMultiSelectManager.selectionActive) {
      assetMultiSelectManager.clear();
      return;
    }
    await goto(Route.albums());
  };

  const refreshAlbum = async () => {
    try {
      album = await getAlbumInfo({ id: album.id, withoutAssets: true });
    } catch (error) {
      await handleLostAlbumAccess({ kind: classifyAlbumAccessError(error) });
    }
  };

  const setModeToView = async () => {
    timelineManager.suspendTransitions = true;
    viewMode = AlbumPageViewMode.VIEW;
    await navigate(
      { targetRoute: 'current', assetId: null, assetGridRouteSearchParams: { at: oldAt?.at } },
      { replaceState: true, forceNavigate: true },
    );
    oldAt = null;
  };

  const handleCloseSelectAssets = async () => {
    timelineMultiSelectManager.clear();
    await setModeToView();
  };

  const enterSelectAssetsMode = async () => {
    timelineManager.suspendTransitions = true;
    viewMode = AlbumPageViewMode.SELECT_ASSETS;
    oldAt = { at: assetViewerManager.gridScrollTarget?.at };
    await navigate(
      { targetRoute: 'current', assetId: null, assetGridRouteSearchParams: { at: null } },
      { replaceState: true },
    );
  };

  const handleAddPhotos = async () => {
    const access = await checkAlbumEditAccess(album.id, $user.id);
    if (access.kind === 'allowed') {
      album = access.album;
      await enterSelectAssetsMode();
      return;
    }

    if (access.kind === 'view_only') {
      album = access.album;
      notifyAlbumAccessResult(access);
      return;
    }

    await handleLostAlbumAccess(access);
  };

  const handleSetVisibility = (assetIds: string[]) => {
    timelineManager.removeAssets(assetIds);
    assetMultiSelectManager.clear();
  };

  const handleRemoveAssets = async (assetIds: string[]) => {
    timelineManager.removeAssets(assetIds);
    await refreshAlbum();
  };

  const handleUndoRemoveAssets = async (assets: TimelineAsset[]) => {
    timelineManager.upsertAssets(assets);
    await refreshAlbum();
  };

  const handleUpdateThumbnail = async (assetId: string) => {
    if (viewMode !== AlbumPageViewMode.SELECT_THUMBNAIL) {
      return;
    }

    await updateThumbnail(assetId);

    viewMode = AlbumPageViewMode.VIEW;
    assetMultiSelectManager.clear();
  };

  const updateThumbnailUsingCurrentSelection = async () => {
    if (assetMultiSelectManager.assets.length === 1) {
      const [firstAsset] = assetMultiSelectManager.assets;
      assetMultiSelectManager.clear();
      await updateThumbnail(firstAsset.id);
    }
  };

  const updateThumbnail = async (assetId: string) => {
    try {
      const response = await updateAlbumInfo({
        id: album.id,
        updateAlbumDto: {
          albumThumbnailAssetId: assetId,
        },
      });
      eventManager.emit('AlbumUpdate', response);
      toastManager.primary($t('album_cover_updated'));
    } catch (error) {
      handleError(error, $t('errors.unable_to_update_album_cover'));
    }
  };

  let album = $derived(data.album);
  let albumId = $derived(album.id);

  onNavigate(async ({ to }) => {
    // Use live album state (not data.album) so assetCount reflects photos added this session.
    const currentAlbum = album;
    if (!currentAlbum) {
      return;
    }

    // Stay within the albums section (list or detail) without treating empty drafts as abandoned.
    if (to?.route.id?.startsWith('/(user)/albums')) {
      return;
    }

    if (currentAlbum.assetCount === 0 && !currentAlbum.albumName) {
      await handleDeleteAlbum(currentAlbum, { notify: false, prompt: false });
    }
  });

  const containsEditors = $derived(album?.shared && album.albumUsers.some(({ role }) => role === AlbumUserRole.Editor));
  const albumUsers = $derived(
    showAlbumUsers && containsEditors ? [album.owner, ...album.albumUsers.map(({ user }) => user)] : [],
  );

  $effect(() => {
    if (!album.isActivityEnabled && activityManager.commentCount === 0) {
      assetViewerManager.closeActivityPanel();
    }
  });

  const options = $derived.by(() => {
    if (viewMode === AlbumPageViewMode.SELECT_ASSETS) {
      return {
        visibility: AssetVisibility.Timeline,
        withPartners: true,
        timelineAlbumId: albumId,
      };
    }
    return { albumId, order: album.order };
  });

  const isShared = $derived(viewMode === AlbumPageViewMode.SELECT_ASSETS ? false : album.albumUsers.length > 0);

  $effect(() => {
    if (assetViewerManager.isViewing || !isShared) {
      return;
    }

    handlePromiseError(activityManager.init(album.id));
  });

  onDestroy(() => activityManager.reset());

  let isOwned = $derived($user.id == album.ownerId);

  let showActivityStatus = $derived(
    album.albumUsers.length > 0 &&
      !assetViewerManager.isViewing &&
      (album.isActivityEnabled || activityManager.commentCount > 0),
  );
  let isEditor = $derived(
    album.albumUsers.find(({ user: { id } }) => id === $user.id)?.role === AlbumUserRole.Editor ||
      album.ownerId === $user.id,
  );

  let albumHasViewers = $derived(album.albumUsers.some(({ role }) => role === AlbumUserRole.Viewer));
  const isSelectionMode = $derived(
    viewMode === AlbumPageViewMode.SELECT_ASSETS ? true : viewMode === AlbumPageViewMode.SELECT_THUMBNAIL,
  );
  const singleSelect = $derived(
    viewMode === AlbumPageViewMode.SELECT_ASSETS ? false : viewMode === AlbumPageViewMode.SELECT_THUMBNAIL,
  );
  const showArchiveIcon = $derived(viewMode !== AlbumPageViewMode.SELECT_ASSETS);
  const onSelect = ({ id }: { id: string }) => {
    if (viewMode !== AlbumPageViewMode.SELECT_ASSETS) {
      void handleUpdateThumbnail(id);
    }
  };
  const currentAssetIntersection = $derived(
    viewMode === AlbumPageViewMode.SELECT_ASSETS ? timelineMultiSelectManager : assetMultiSelectManager,
  );

  const onSharedLinkCreate = async () => {
    await refreshAlbum();
  };

  const onAlbumDelete = async (deletedAlbum: AlbumResponseDto) => {
    if (deletedAlbum.id !== album.id) {
      return;
    }

    if (deletedAlbum.ownerId !== $user.id) {
      toastManager.danger($t('album_deleted_by_owner'));
    }

    await goto(Route.albums());
    viewMode = AlbumPageViewMode.VIEW;
  };

  const onAlbumAddAssets = async ({ albumIds }: { albumIds: string[] }) => {
    if (!albumIds.includes(album.id)) {
      return;
    }

    await refreshAlbum();
    timelineMultiSelectManager.clear();
    await setModeToView();
  };

  const onAlbumShare = async () => {
    await refreshAlbum();
    await setModeToView();
  };

  const onAlbumUserUpdate = ({ albumId, userId, role }: { albumId: string; userId: string; role: AlbumUserRole }) => {
    if (albumId !== album.id) {
      return;
    }

    const albumUsers = album.albumUsers.map((albumUser) =>
      albumUser.user.id === userId ? { ...albumUser, role } : albumUser,
    );
    album = { ...album, albumUsers };

    if (userId === $user.id && role !== AlbumUserRole.Editor && viewMode === AlbumPageViewMode.SELECT_ASSETS) {
      notifyAlbumAccessResult({ kind: 'view_only', album });
      void handleCloseSelectAssets();
    }
  };

  const onAlbumUserDelete = async ({ albumId, userId }: { albumId: string; userId: string }) => {
    if (albumId !== album.id) {
      return;
    }

    if (userId === $user.id) {
      await handleLostAlbumAccess({ kind: 'access_denied' });
      return;
    }

    await refreshAlbum();
  };

  const onAlbumAccessLost = async ({
    albumId,
    result,
  }: {
    albumId: string;
    result: AlbumEditAccessResult;
  }) => {
    if (albumId !== album.id) {
      return;
    }

    if (result.kind === 'view_only') {
      album = result.album;
      if (viewMode === AlbumPageViewMode.SELECT_ASSETS) {
        await handleCloseSelectAssets();
      }
      return;
    }

    // Redirect is handled by the emitter for access_denied / deleted.
    viewMode = AlbumPageViewMode.VIEW;
  };

  const onAlbumUpdate = async (newAlbum: AlbumResponseDto) => {
    album = newAlbum;

    await invalidate('album:data');
  };

  const { Cast } = $derived(getGlobalActions($t));
  const { Share } = $derived(getAlbumActions($t, album));
  const { AddAssets, Upload } = $derived(getAlbumAssetsActions($t, album, timelineMultiSelectManager.assets));

  const Close = $derived({
    title: $t('go_back'),
    type: $t('command'),
    icon: mdiArrowLeft,
    onAction: handleEscape,
    $if: () => !assetViewerManager.isViewing,
    shortcuts: { key: 'Escape' },
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

    const asset = assetMultiSelectManager.selectedAssets.length > 0 ? firstSelectedAsset : firstAsset;

    if (asset) {
      handlePromiseError(
        assetViewerManager.setAssetId(asset.id).then(() => ($slideshowState = SlideshowState.PlaySlideshow)),
      );
    }
  };

  const handleRemoveFromAlbum = async () => {
    const ids = assetMultiSelectManager.assets.map(({ id }) => id);

    const isConfirmed = await modalManager.showDialog({
      prompt: $t('remove_assets_album_confirmation', { values: { count: ids.length } }),
    });

    if (!isConfirmed) {
      return;
    }

    try {
      const results = await removeAssetFromAlbum({
        id: album.id,
        bulkIdsDto: { ids },
      });

      await handleRemoveAssets(ids);

      const count = results.filter(({ success }) => success).length;
      toastManager.primary($t('assets_removed_count', { values: { count } }));

      assetMultiSelectManager.clear();
    } catch (error) {
      handleError(error, $t('errors.error_removing_assets_from_album'));
    }
  };

  const SetAsAlbumCover: ActionItem = {
    title: $t('set_as_album_cover'),
    icon: mdiImageOutline,
    $if: () => assetMultiSelectManager.assets.length === 1,
    onAction: () => {
      void updateThumbnailUsingCurrentSelection();
    },
  };

  const RemoveFromAlbumItem: ActionItem = {
    title: $t('remove_from_album'),
    icon: mdiImageRemoveOutline,
    $if: () => isOwned || assetMultiSelectManager.isAllUserOwned,
    onAction: () => {
      void handleRemoveFromAlbum();
    },
  };

  const owned = $derived(assetMultiSelectManager.isAllUserOwned);

  const menuItems = $derived(
    getAssetSelectMenuItems($t, {
      showSlideshow: true,
      onStartSlideshow: () => {
        void handleStartSlideshow();
      },
      filename: `${album.albumName}.zip`,
      showChangeDate: owned,
      showChangeDescription: owned,
      showChangeLocation: owned,
      showArchive: owned,
      unarchive: assetMultiSelectManager.isAllArchived,
      onArchive: (ids, visibility) => timelineManager.update(ids, (asset) => (asset.visibility = visibility)),
      showVisibility: owned,
      onVisibilitySet: handleSetVisibility,
      showTag: owned,
      showDelete: owned,
      onAssetDelete: (assetIds) => {
        void handleRemoveAssets(assetIds);
      },
      onUndoDelete: (assets) => {
        void handleUndoRemoveAssets(assets);
      },
      extraItems: [SetAsAlbumCover, RemoveFromAlbumItem],
    }),
  );

  const albumOptionsItems = $derived([
    containsEditors
      ? {
          title: $t('view_asset_owners'),
          icon: showAlbumUsers ? mdiAccountEye : mdiAccountEyeOutline,
          onAction: () => timelineManager.toggleShowAssetOwners(),
        }
      : undefined,
    isOwned && album.assetCount > 0
      ? {
          title: $t('select_album_cover'),
          icon: mdiImageOutline,
          onAction: () => {
            viewMode = AlbumPageViewMode.SELECT_THUMBNAIL;
          },
        }
      : undefined,
    isOwned && album.assetCount > 0
      ? {
          title: $t('options'),
          icon: mdiCogOutline,
          onAction: () => modalManager.show(AlbumOptionsModal, { album }),
        }
      : undefined,
    isOwned
      ? {
          title: $t('delete_album'),
          icon: mdiTrashCanOutline,
          onAction: () => handleDeleteAlbum(album),
        }
      : undefined,
  ] satisfies Array<ActionItem | undefined>);
</script>

<OnEvents
  {onSharedLinkCreate}
  onSharedLinkDelete={refreshAlbum}
  {onAlbumDelete}
  {onAlbumAddAssets}
  {onAlbumShare}
  {onAlbumUserUpdate}
  {onAlbumUserDelete}
  {onAlbumAccessLost}
  {onAlbumUpdate}
/>
<CommandPaletteDefaultProvider name={$t('album')} actions={[AddAssets, Upload, Close]} />

<div class="flex overflow-hidden" use:scrollMemoryClearer={{ routeStartsWith: Route.albums() }}>
  <div class="relative w-full shrink">
    <main
      class="relative h-dvh overflow-hidden px-2 md:px-6 max-md:pt-(--navbar-height-md) pt-[calc(var(--navbar-height)+30px)]"
    >
      <Timeline
        enableRouting={viewMode === AlbumPageViewMode.SELECT_ASSETS ? false : true}
        {album}
        {albumUsers}
        bind:timelineManager
        {options}
        assetInteraction={currentAssetIntersection}
        {isShared}
        {isSelectionMode}
        {singleSelect}
        {showArchiveIcon}
        {onSelect}
        onEscape={handleEscape}
        selectedAssets={assetMultiSelectManager.selectedAssets}
        {shuffledSelectedAssets}
      >
        {#if viewMode !== AlbumPageViewMode.SELECT_ASSETS}
          {#if viewMode !== AlbumPageViewMode.SELECT_THUMBNAIL}
            <!-- ALBUM TITLE -->
            <section class="pt-8 md:pt-24">
              <AlbumTitle
                id={album.id}
                albumName={album.albumName}
                {isOwned}
                onUpdate={(albumName) => (album = { ...album, albumName })}
              />

              {#if album.assetCount > 0}
                <AlbumSummary {album} />
              {/if}

              <!-- ALBUM SHARING -->
              {#if album.albumUsers.length > 0 || (album.hasSharedLink && isOwned)}
                <div class="my-3 flex gap-x-1">
                  <!-- link -->
                  {#if album.hasSharedLink && isOwned}
                    <IconButton
                      aria-label={$t('create_link_to_share')}
                      color="secondary"
                      size="medium"
                      shape="round"
                      icon={mdiLink}
                      onclick={() => modalManager.show(SharedLinkCreateModal, { albumId: album.id })}
                    />
                  {/if}

                  <!-- owner -->
                  <button type="button" onclick={() => modalManager.show(AlbumOptionsModal, { album })}>
                    <UserAvatar user={album.owner} size="md" />
                  </button>

                  <!-- users with write access (collaborators) -->
                  {#each album.albumUsers.filter(({ role }) => role === AlbumUserRole.Editor) as { user } (user.id)}
                    <button type="button" onclick={() => modalManager.show(AlbumOptionsModal, { album })}>
                      <UserAvatar {user} size="md" />
                    </button>
                  {/each}

                  <!-- display ellipsis if there are readonly users too -->
                  {#if albumHasViewers}
                    <IconButton
                      shape="round"
                      aria-label={$t('view_all_users')}
                      color="secondary"
                      size="medium"
                      icon={mdiDotsVertical}
                      onclick={() => modalManager.show(AlbumOptionsModal, { album })}
                    />
                  {/if}

                  <ActionButton action={Share} />
                </div>
              {/if}
              <AlbumDescription
                id={album.id}
                {isOwned}
                bind:description={() => album.description, (description) => (album = { ...album, description })}
              />
            </section>
          {/if}

          {#if album.assetCount === 0 && isEditor}
            <section id="empty-album" class="flex place-content-center place-items-center">
              <div class="w-full max-w-100 md:w-auto">
                <p class="p-4 uppercase text-xs font-medium">{$t('add_photos')}</p>
                <button
                  type="button"
                  onclick={() => void handleAddPhotos()}
                  class="w-full md:w-[320px] h-[104px] flex place-items-center gap-6 border px-8 py-8 transition-all hover:bg-gray-100 dark:hover:bg-gray-500/20 hover:text-primary-700 rounded-[20px] bg-immich-gray-file-loader border-immich-gray-border dark:border-immich-dark-gray-border dark:bg-immich-dark-bg-gray"
                >
                  <span class="text-primary-700">
                    <Icon icon={mdiPlus} size="24" />
                  </span>
                  <span>{$t('select_photos')}</span>
                </button>
              </div>
            </section>
          {/if}
        {/if}
      </Timeline>

      {#if showActivityStatus}
        <div class="absolute z-2 bottom-0 end-0 mb-6 me-12">
          <ActivityStatus
            disabled={!album.isActivityEnabled}
            isLiked={activityManager.isLiked}
            numberOfComments={activityManager.commentCount}
            numberOfLikes={undefined}
            onFavorite={handleFavorite}
          />
        </div>
      {/if}
    </main>

    {#if assetMultiSelectManager.selectionActive}
      <AssetSelectControlBar>
        {@const Actions = getAssetBulkActions($t)}
        <CommandPaletteDefaultProvider name={$t('assets')} actions={Object.values(Actions)} />
        <CreateSharedLink />
        <SelectAllAssets {timelineManager} assetInteraction={assetMultiSelectManager} />
        <ActionButton action={Actions.AddToAlbum} />
        {#if assetMultiSelectManager.isAllUserOwned}
          <FavoriteAction
            removeFavorite={assetMultiSelectManager.isAllFavorite}
            onFavorite={(ids, isFavorite) => timelineManager.update(ids, (asset) => (asset.isFavorite = isFavorite))}
          ></FavoriteAction>
        {/if}
        <ContextMenuButton icon={mdiDotsVertical} aria-label={$t('menu')} items={menuItems} />
      </AssetSelectControlBar>
    {:else}
      {#if viewMode === AlbumPageViewMode.VIEW}
        <ControlAppBar showBackButton backIcon={mdiArrowLeft} onClose={() => goto(Route.albums())}>
          {#snippet trailing()}
            <ActionButton action={Cast} />

            {#if isEditor}
              <IconButton
                variant="ghost"
                shape="round"
                color="secondary"
                aria-label={$t('add_photos')}
                onclick={() => void handleAddPhotos()}
                icon={mdiImagePlusOutline}
              />
            {/if}

            <ActionButton action={Share} />

            {#if featureFlagsManager.value.map}
              <AlbumMap {album} />
            {/if}

            {#if album.assetCount > 0}
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
                variant="ghost"
                color="secondary"
                aria-label={$t('download')}
                onclick={() => handleDownloadAlbum(album)}
                icon={mdiDownload}
              />
            {/if}

            {#if isOwned || containsEditors}
              <ContextMenuButton
                icon={mdiDotsVertical}
                aria-label={$t('album_options')}
                color="secondary"
                items={albumOptionsItems}
              />
            {/if}
          {/snippet}
        </ControlAppBar>
      {/if}

      {#if viewMode === AlbumPageViewMode.SELECT_ASSETS}
        <ControlAppBar onClose={handleCloseSelectAssets}>
          {#snippet leading()}
            <p class="text-lg dark:text-immich-dark-fg w-40">
              {#if !timelineMultiSelectManager.selectionActive}
                {$t('add_to_album')}
              {:else}
                {$t('selected_count', { values: { count: timelineMultiSelectManager.assets.length } })}
              {/if}
            </p>
          {/snippet}

          {#snippet trailing()}
            <HeaderActionButton action={Upload} />
            <HeaderActionButton action={AddAssets} />
          {/snippet}
        </ControlAppBar>
      {/if}

      {#if viewMode === AlbumPageViewMode.SELECT_THUMBNAIL}
        <ControlAppBar onClose={() => (viewMode = AlbumPageViewMode.VIEW)}>
          {#snippet leading()}
            {$t('select_album_cover')}
          {/snippet}
        </ControlAppBar>
      {/if}
    {/if}
  </div>
  {#if album.albumUsers.length > 0 && album && assetViewerManager.isShowActivityPanel && $user && !assetViewerManager.isViewing}
    <div class="flex">
      <div
        transition:fly={{ duration: 150 }}
        id="activity-panel"
        class="z-2 w-90 md:w-115 overflow-y-auto transition-all dark:border-l dark:border-s-immich-dark-gray"
        translate="yes"
      >
        <ActivityViewer
          user={$user}
          disabled={!album.isActivityEnabled}
          albumOwnerId={album.ownerId}
          albumId={album.id}
        />
      </div>
    </div>
  {/if}
</div>

<style>
  ::placeholder {
    color: rgb(60, 60, 60);
    opacity: 0.6;
  }

  ::-ms-input-placeholder {
    /* Edge 12 -18 */
    color: white;
  }
</style>
