<script lang="ts">
  import AlbumCover from '$lib/components/album-page/album-cover.svelte';
  import { user } from '$lib/stores/user.store';
  import { getContextMenuPositionFromEvent, type ContextMenuPosition } from '$lib/utils/context-menu';
  import { getShortDateRange } from '$lib/utils/date-time';
  import type { AlbumResponseDto } from '@immich/sdk';
  import { IconButton } from '@immich/ui';
  import { mdiDotsVertical } from '@mdi/js';
  import { t } from 'svelte-i18n';

  interface Props {
    album: AlbumResponseDto;
    showOwner?: boolean;
    showDateRange?: boolean;
    showItemCount?: boolean;
    preload?: boolean;
    onShowContextMenu?: ((position: ContextMenuPosition) => unknown | Promise<unknown>) | undefined;
  }

  let {
    album,
    showOwner = false,
    showDateRange = false,
    showItemCount = false,
    preload = false,
    onShowContextMenu = undefined,
  }: Props = $props();

  let menuOpen = $state(false);

  const showAlbumContextMenu = async (e: MouseEvent) => {
    e.stopPropagation();
    e.preventDefault();
    if (!onShowContextMenu) {
      return;
    }

    menuOpen = true;
    try {
      await onShowContextMenu(getContextMenuPositionFromEvent(e));
    } finally {
      menuOpen = false;
    }
  };
</script>

<div
  class="group relative rounded-2xl border border-transparent md:p-[11px] hover:bg-gray-100 hover:border-gray-200 dark:hover:border-gray-800 dark:hover:bg-immich-dark-gray md:w-69"
  data-testid="album-card"
>
  {#if onShowContextMenu}
    <div
      id="icon-{album.id}"
      class="absolute end-6 top-6 transition-opacity {menuOpen
        ? 'opacity-100'
        : 'opacity-0 group-hover:opacity-100 has-focus-visible:opacity-100'}"
      data-testid="context-button-parent"
    >
      <IconButton
        aria-label={$t('show_album_options')}
        icon={mdiDotsVertical}
        shape="round"
        variant="ghost"
        size="medium"
        class="icon-white-drop-shadow text-white bg-black hover:bg-black"
        onclick={showAlbumContextMenu}
      />
    </div>
  {/if}

  <AlbumCover {album} {preload} class="transition-all duration-300 hover:shadow-lg w-full! md:w-63!" />

  <div class="mt-5">
    <p
      class="w-full leading-6 text-xl font-bold text-black dark:text-white group-hover:text-immich-primary dark:group-hover:text-immich-dark-primary"
      data-testid="album-name"
      title={album.albumName}
    >
      {album.albumName}
    </p>

    {#if showDateRange && album.startDate && album.endDate}
      <p class="flex font-medium capitalize">
        {getShortDateRange(album.startDate, album.endDate)}
      </p>
    {/if}

    <span class="flex gap-0.5" data-testid="album-details">
      {#if showItemCount}
        <p>
          {$t('items_count', { values: { count: album.assetCount } })}
        </p>
      {/if}

      {#if (showOwner || album.shared) && showItemCount}
        <p class="w-3 text-center">•</p>
      {/if}

      {#if showOwner}
        {#if $user.id === album.ownerId}
          <p>{$t('owned')}</p>
        {:else if album.owner}
          <p>{$t('shared_by_user', { values: { user: album.owner.name } })}</p>
        {:else}
          <p>{$t('shared')}</p>
        {/if}
      {:else if album.shared}
        <p>{$t('shared')}</p>
      {/if}
    </span>
  </div>
</div>
