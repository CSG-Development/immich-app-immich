<script lang="ts">
  import { goto } from '$app/navigation';
  import { resolveRoute } from '$app/paths';
  import Icon from '$lib/components/elements/icon.svelte';
  import { AppRoute, dateFormats } from '$lib/constants';
  import { locale } from '$lib/stores/preferences.store';
  import { user } from '$lib/stores/user.store';
  import type { ContextMenuPosition } from '$lib/utils/context-menu';
  import type { AlbumResponseDto } from '@immich/sdk';
  import { mdiShareVariantOutline } from '@mdi/js';
  import { t } from 'svelte-i18n';

  interface Props {
    album: AlbumResponseDto;
    onShowContextMenu?: ((position: ContextMenuPosition, album: AlbumResponseDto) => unknown) | undefined;
  }

  let { album, onShowContextMenu = undefined }: Props = $props();

  const showContextMenu = (position: ContextMenuPosition) => {
    onShowContextMenu?.(position, album);
  };

  const dateLocaleString = (dateString: string) => {
    return new Date(dateString).toLocaleDateString($locale, dateFormats.album);
  };

  const oncontextmenu = (event: MouseEvent) => {
    event.preventDefault();
    showContextMenu({ x: event.x, y: event.y });
  };
</script>

<tr
  class="flex h-[50px] w-full place-items-center border-[3px] border-transparent p-2 text-center even:bg-subtle/20 odd:bg-subtle/80 hover:cursor-pointer hover:border-immich-primary/75 odd:dark:bg-immich-dark-gray/75 even:dark:bg-immich-dark-gray/50 dark:hover:border-immich-dark-primary/75 md:p-5"
  onclick={() => goto(resolveRoute(`${AppRoute.ALBUMS}/${album.id}`, {}))}
  {oncontextmenu}
>
  <td class="text-md text-ellipsis text-start w-8/12 sm:w-4/12 md:w-4/12 xl:w-[30%] 2xl:w-[40%] items-center">
    {album.albumName}
    {#if album.shared}
      <Icon
        path={mdiShareVariantOutline}
        size="16"
        class="inline ms-1 opacity-70"
        title={album.ownerId === $user.id
          ? $t('shared_by_you')
          : $t('shared_by_user', { values: { user: album.owner.name } })}
      />
    {/if}
  </td>
  <td class="text-md text-ellipsis text-center sm:w-2/12 md:w-2/12 xl:w-[15%] 2xl:w-[12%]">
    {$t('items_count', { values: { count: album.assetCount } })}
  </td>
  <td class="text-md hidden text-ellipsis text-center sm:block w-3/12 xl:w-[15%] 2xl:w-[12%]">
    {dateLocaleString(album.updatedAt)}
  </td>
  <td class="text-md hidden text-ellipsis text-center sm:block w-3/12 xl:w-[15%] 2xl:w-[12%]">
    {dateLocaleString(album.createdAt)}
  </td>
  <td class="text-md text-ellipsis text-center hidden xl:block xl:w-[15%] 2xl:w-[12%]">
    {#if album.endDate}
      {dateLocaleString(album.endDate)}
    {:else}
      -
    {/if}
  </td>
  <td class="text-md text-ellipsis text-center hidden xl:block xl:w-[15%] 2xl:w-[12%]">
    {#if album.startDate}
      {dateLocaleString(album.startDate)}
    {:else}
      -
    {/if}
  </td>
</tr>
