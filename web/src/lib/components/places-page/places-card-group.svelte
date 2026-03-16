<script lang="ts">
  import { resolve } from '$app/paths';
  import Icon from '$lib/components/elements/icon.svelte';
  import { AppRoute } from '$lib/constants';
  import { mobileDevice } from '$lib/stores/mobile-device.svelte';
  import { placesViewSettings } from '$lib/stores/preferences.store';
  import { getAssetThumbnailUrl } from '$lib/utils';
  import { getMetadataSearchQuery } from '$lib/utils/metadata-search';
  import { type PlacesGroup, isPlacesGroupCollapsed, togglePlacesGroupCollapsing } from '$lib/utils/places-utils';
  import { AssetMediaSize, type AssetResponseDto } from '@immich/sdk';
  import { mdiChevronRight } from '@mdi/js';
  import { t } from 'svelte-i18n';

  interface Props {
    places: AssetResponseDto[];
    group?: PlacesGroup | undefined;
  }

  let { places, group = undefined }: Props = $props();

  let isCollapsed = $derived(!!group && isPlacesGroupCollapsed($placesViewSettings, group.id));
  let iconRotation = $derived(isCollapsed ? 'rotate-0' : 'rotate-90');

  const grid = $derived(document.querySelector('#grid'));

  $effect(() => {
    if (grid && places.length >= 3 && mobileDevice.maxMd) {
      grid.classList.remove('justify-start');
      grid.classList.add('justify-around');
    } else {
      grid?.classList.remove('justify-around');
      grid?.classList.add('justify-start');
    }
  });
</script>

{#if group}
  <div class="my-2">
    <button
      type="button"
      onclick={() => togglePlacesGroupCollapsing(group.id)}
      class="h-12 dark:text-immich-dark-fg flex items-center gap-x-1"
      aria-expanded={!isCollapsed}
    >
      <Icon path={mdiChevronRight} size="24" class="transition-all duration-250 {iconRotation}" />
      <span class="font-bold text-2xl/8 text-black dark:text-white">{group.name}</span>
      <span class="font-medium">({$t('places_count', { values: { count: places.length } })})</span>
    </button>
    <hr class="dark:border-immich-dark-gray" />
  </div>
{/if}

<div class:md:my-6={!isCollapsed} class:my-4={!isCollapsed}>
  {#if !isCollapsed}
    <div
      id="grid"
      class="grid grid-cols-[repeat(auto-fit,minmax(6.625rem,max-content))] md:grid-cols-[repeat(auto-fit,minmax(10rem,max-content))] gap-[9px] md:gap-4"
    >
      {#each places as item (item.id)}
        {@const city = item.exifInfo?.city}
        <a
          class="relative md:w-40 w-26.5"
          href={resolve(`${AppRoute.SEARCH}?${getMetadataSearchQuery({ city })}`)}
          draggable="false"
        >
          <div class="flex justify-center overflow-hidden rounded-xl brightness-75 filter">
            <img
              src={getAssetThumbnailUrl({ id: item.id, size: AssetMediaSize.Thumbnail })}
              alt={city}
              class="object-cover aspect-square w-full"
            />
          </div>
          <span
            class="w-100 absolute bottom-2 w-full text-ellipsis px-1 text-center text-sm font-medium capitalize text-white hover:cursor-pointer"
          >
            {city}
          </span>
        </a>
      {/each}
    </div>
  {/if}
</div>
