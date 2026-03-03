<script lang="ts">
  import Icon from '$lib/components/elements/icon.svelte';
  import { AlbumSortBy, albumViewSettings, SortOrder } from '$lib/stores/preferences.store';
  import type { AlbumSortOptionMetadata } from '$lib/utils/album-utils';
  import { mdiArrowDown, mdiArrowUp } from '@mdi/js';
  import { t } from 'svelte-i18n';

  interface Props {
    option: AlbumSortOptionMetadata;
  }

  let { option }: Props = $props();

  const handleSort = () => {
    if ($albumViewSettings.sortBy === option.id) {
      $albumViewSettings.sortOrder = $albumViewSettings.sortOrder === SortOrder.Asc ? SortOrder.Desc : SortOrder.Asc;
    } else {
      $albumViewSettings.sortBy = option.id;
      $albumViewSettings.sortOrder = option.defaultOrder;
    }
  };

  let albumSortByNames: Record<AlbumSortBy, string> = $derived({
    [AlbumSortBy.Title]: $t('sort_title'),
    [AlbumSortBy.ItemCount]: $t('sort_items'),
    [AlbumSortBy.DateModified]: $t('sort_modified'),
    [AlbumSortBy.DateCreated]: $t('sort_created'),
    [AlbumSortBy.MostRecentPhoto]: $t('sort_recent'),
    [AlbumSortBy.OldestPhoto]: $t('sort_oldest'),
  });
</script>

<th class="text-sm font-medium {option.columnStyle} bg-white">
  <button
    type="button"
    class="rounded-lg p-2 bg-white flex items-center overflow-hidden whitespace-nowrap text-ellipsis"
    onclick={handleSort}
  >
    {#if $albumViewSettings.sortBy === option.id}
      {#if $albumViewSettings.sortOrder === SortOrder.Desc}
        <Icon path={mdiArrowDown} size="24" />
      {:else}
        <Icon path={mdiArrowUp} size="24" />
      {/if}
    {:else}
      <div class="w-6 h-6"></div>
    {/if}
    {albumSortByNames[option.id]}
  </button>
</th>
