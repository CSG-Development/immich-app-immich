<script lang="ts">
  import { locale } from '$lib/stores/preferences.store';
  import {
    AssetVisibility,
    getAlbumStatistics,
    getAssetStatistics,
    type AlbumStatisticsResponseDto,
    type AssetStatsResponseDto,
  } from '@immich/sdk';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  let timelineStats: AssetStatsResponseDto = $state({
    videos: 0,
    images: 0,
    total: 0,
  });

  let favoriteStats: AssetStatsResponseDto = $state({
    videos: 0,
    images: 0,
    total: 0,
  });

  let archiveStats: AssetStatsResponseDto = $state({
    videos: 0,
    images: 0,
    total: 0,
  });

  let trashStats: AssetStatsResponseDto = $state({
    videos: 0,
    images: 0,
    total: 0,
  });

  let albumStats: AlbumStatisticsResponseDto = $state({
    owned: 0,
    shared: 0,
    notShared: 0,
  });

  const getUsage = async () => {
    [timelineStats, favoriteStats, archiveStats, trashStats, albumStats] = await Promise.all([
      getAssetStatistics({ visibility: AssetVisibility.Timeline }),
      getAssetStatistics({ isFavorite: true }),
      getAssetStatistics({ visibility: AssetVisibility.Archive }),
      getAssetStatistics({ isTrashed: true }),
      getAlbumStatistics(),
    ]);
  };

  onMount(async () => {
    await getUsage();
  });
</script>

{#snippet row(viewName: string, stats: AssetStatsResponseDto)}
  <tr
    class="flex h-14 w-full place-items-center text-center dark:text-immich-dark-fg odd:bg-white odd:dark:bg-immich-dark-gray-card even:bg-immich-bg-gray/75 even:dark:bg-immich-dark-bg-gray/75"
  >
    <td class="w-1/4 px-4 text-sm">{viewName}</td>
    <td class="w-1/4 px-4 text-sm">{stats.images.toLocaleString($locale)}</td>
    <td class="w-1/4 px-4 text-sm">{stats.videos.toLocaleString($locale)}</td>
    <td class="w-1/4 px-4">{stats.total.toLocaleString($locale)}</td>
  </tr>
{/snippet}

<section class="ms-6 my-6">
  <p class="font-medium text-primary">{$t('photos_and_videos')}</p>
  <div class="overflow-x-auto">
    <table class="w-full text-start mt-4">
      <thead
        class="mb-4 flex h-11 w-full rounded-md border immich-border bg-immich-bg-gray-mt text-primary dark:bg-immich-dark-bg-gray-mt"
      >
        <tr class="flex w-full place-items-center text-sm font-medium text-center">
          <th class="w-1/4">{$t('view_name')}</th>
          <th class="w-1/4">{$t('photos')}</th>
          <th class="w-1/4">{$t('videos')}</th>
          <th class="w-1/4">{$t('total')}</th>
        </tr>
      </thead>
      <tbody class="block w-full overflow-y-auto rounded-md border immich-border">
        {@render row($t('timeline'), timelineStats)}
        {@render row($t('favorites'), favoriteStats)}
        {@render row($t('archive'), archiveStats)}
        {@render row($t('trash'), trashStats)}
      </tbody>
    </table>
  </div>

  <div class="mt-6">
    <p class="text-primary">{$t('albums')}</p>
  </div>
  <div class="overflow-x-auto">
    <table class="w-full text-start mt-4">
      <thead
        class="mb-4 flex h-11 w-full rounded-md border immich-border bg-immich-bg-gray-mt text-primary dark:bg-immich-dark-bg-gray-mt"
      >
        <tr class="flex w-full place-items-center text-sm font-medium text-center">
          <th class="w-1/2">{$t('owned')}</th>
          <th class="w-1/2">{$t('shared')}</th>
        </tr>
      </thead>
      <tbody class="block w-full overflow-y-auto rounded-md border immich-border">
        <tr
          class="flex h-11 w-full place-items-center text-center dark:text-immich-dark-fg bg-white dark:bg-immich-dark-gray-card"
        >
          <td class="w-1/2 px-4 text-sm">{albumStats.owned.toLocaleString($locale)}</td>
          <td class="w-1/2 px-4 text-sm">{albumStats.shared.toLocaleString($locale)}</td>
        </tr>
      </tbody>
    </table>
  </div>
</section>
