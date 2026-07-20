<script lang="ts">
  import LoadingDots from '$lib/components/LoadingDots.svelte';
  import RatingAction from '$lib/components/asset-viewer/actions/rating-action.svelte';
  import DeleteAction from '$lib/components/asset-viewer/actions/delete-action.svelte';
  import type { OnAction, PreAction } from '$lib/components/asset-viewer/actions/action';
  import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
  import { languageManager } from '$lib/managers/language-manager.svelte';
  import { getGlobalActions } from '$lib/services/app.service';
  import { getAssetActions } from '$lib/services/asset.service';
  import { getAssetViewerMoreMenuItems } from '$lib/services/asset-viewer-menu.service';
  import { user } from '$lib/stores/user.store';
  import { getSharedLink, withoutIcons } from '$lib/utils';
  import type { OnUndoDelete } from '$lib/utils/actions';
  import {
    type AlbumResponseDto,
    type AssetResponseDto,
    type PersonResponseDto,
    type StackResponseDto,
  } from '@immich/sdk';
  import { ActionButton, CommandPaletteDefaultProvider, ContextMenuButton, Tooltip, type ActionItem } from '@immich/ui';
  import { mdiArrowLeft, mdiArrowRight, mdiDotsVertical } from '@mdi/js';
  import { t } from 'svelte-i18n';

  interface Props {
    asset: AssetResponseDto;
    album?: AlbumResponseDto | null;
    person?: PersonResponseDto | null;
    stack?: StackResponseDto | null;
    showSlideshow?: boolean;
    preAction: PreAction;
    onAction: OnAction;
    onUndoDelete?: OnUndoDelete;
    onPlaySlideshow: () => void;
    onClose?: () => void;
    onRemoveFromAlbum?: (assetIds: string[]) => void;
    playOriginalVideo: boolean;
    setPlayOriginalVideo: (value: boolean) => void;
  }

  let {
    asset,
    album = null,
    person = null,
    stack = null,
    showSlideshow = false,
    preAction,
    onAction,
    onUndoDelete = undefined,
    onPlaySlideshow,
    onClose,
    onRemoveFromAlbum,
    playOriginalVideo = false,
    setPlayOriginalVideo,
  }: Props = $props();

  const isOwner = $derived($user && asset.ownerId === $user?.id);
  const isAlbumOwner = $derived($user && album?.ownerId === $user?.id);

  const { Cast } = $derived(getGlobalActions($t));

  const Close: ActionItem = $derived({
    title: $t('go_back'),
    type: $t('assets'),
    icon: languageManager.rtl ? mdiArrowRight : mdiArrowLeft,
    $if: () => !!onClose && !assetViewerManager.isFaceEditMode,
    onAction: () => onClose?.(),
    shortcuts: [{ key: 'Escape' }],
  });

  const Actions = $derived(getAssetActions($t, asset));
  const moreMenuItems = $derived(
    getAssetViewerMoreMenuItems($t, {
      asset,
      album,
      person,
      stack,
      showSlideshow,
      isOwner: !!isOwner,
      isAlbumOwner: !!isAlbumOwner,
      preAction,
      onAction,
      onPlaySlideshow,
      onRemoveFromAlbum,
      playOriginalVideo,
      setPlayOriginalVideo,
    }),
  );
  const sharedLink = getSharedLink();
</script>

<CommandPaletteDefaultProvider name={$t('assets')} actions={withoutIcons([Close, Cast, ...Object.values(Actions)])} />

<div
  class="flex h-16 place-items-center justify-between bg-linear-to-b from-black/40 px-3 transition-transform duration-200 drop-shadow-[0_0_1px_rgba(0,0,0,0.4)]"
>
  <div class="dark">
    <ActionButton action={Close} />
  </div>

  <div
    class="flex p-1 -m-1 items-center gap-2 overflow-x-auto *:shrink-0 dark"
    data-testid="asset-viewer-navbar-actions"
  >
    {#if assetViewerManager.isImageLoading}
      <Tooltip text={$t('loading')}>
        {#snippet child({ props })}
          <div {...props} role="status" aria-label={$t('loading')}>
            <LoadingDots class="me-1" />
          </div>
        {/snippet}
      </Tooltip>
    {/if}
    <ActionButton action={Cast} />
    <ActionButton action={Actions.Share} />
    <ActionButton action={Actions.Offline} />
    <ActionButton action={Actions.ZoomIn} />
    <ActionButton action={Actions.ZoomOut} />
    <ActionButton action={Actions.PlayMotionPhoto} />
    <ActionButton action={Actions.StopMotionPhoto} />
    <ActionButton action={Actions.Copy} />
    <ActionButton action={Actions.SharedLinkDownload} />
    <ActionButton action={Actions.Info} />
    <ActionButton action={Actions.Favorite} />
    <ActionButton action={Actions.Unfavorite} />

    {#if isOwner}
      <RatingAction {asset} {onAction} />
    {/if}

    <ActionButton action={Actions.Edit} />

    {#if isOwner}
      <DeleteAction {asset} {onAction} {preAction} {onUndoDelete} />
    {/if}

    {#if !sharedLink}
      <ContextMenuButton
        color="secondary"
        position="top-right"
        icon={mdiDotsVertical}
        aria-label={$t('more')}
        items={moreMenuItems}
      />
    {/if}
  </div>
</div>
