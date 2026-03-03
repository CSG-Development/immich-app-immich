<script lang="ts">
  import { resolve } from '$app/paths';
  import emptyPeople from '$lib/assets/empty-people.svg';
  import emptyPlaces from '$lib/assets/empty-places.svg';
  import ImageThumbnail from '$lib/components/assets/thumbnail/image-thumbnail.svelte';
  import Icon from '$lib/components/elements/icon.svelte';
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/empty-placeholder.svelte';
  import SingleGridRow from '$lib/components/shared-components/single-grid-row.svelte';
  import { AppRoute } from '$lib/constants';
  import { websocketEvents } from '$lib/stores/websocket';
  import { getAssetThumbnailUrl, getPeopleThumbnailUrl } from '$lib/utils';
  import { getMetadataSearchQuery } from '$lib/utils/metadata-search';
  import { AssetMediaSize, type SearchExploreResponseDto } from '@immich/sdk';
  import { mdiHeart } from '@mdi/js';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  const getFieldItems = (items: SearchExploreResponseDto[], field: string) => {
    const targetField = items.find((item) => item.fieldName === field);
    return targetField?.items || [];
  };

  let places = $derived(getFieldItems(data.items, 'exifInfo.city'));
  let people = $state(data.response.people);

  let hasPeople = $derived(data.response.total > 0);

  onMount(() => {
    return websocketEvents.on('on_person_thumbnail', (personId: string) => {
      people.map((person) => {
        if (person.id === personId) {
          person.updatedAt = Date.now().toString();
        }
      });
    });
  });
</script>

<UserPageLayout title={data.meta.title}>
  <div class="mt-2">
    <div class="flex justify-between pt-6 pb-8">
      <p class="font-medium dark:text-immich-dark-fg">{$t('people')}</p>
      <a
        href={resolve(AppRoute.PEOPLE)}
        class="pe-4 text-sm hover:text-immich-primary dark:text-immich-dark-fg dark:hover:text-immich-dark-primary"
        draggable="false"
      >
        {$t('view_all')}
      </a>
    </div>
    {#if hasPeople}
      <SingleGridRow class="grid grid-flow-col md:auto-cols-[7.25rem] auto-cols-[4.875rem] md:gap-x-4 gap-x-2">
        {#snippet children({ itemCount })}
          {#each people.slice(0, itemCount) as person (person.id)}
            <a href={resolve(`${AppRoute.PEOPLE}/${person.id}`)} class="text-center relative md:max-w-29 max-w-19.5">
              <ImageThumbnail
                circle
                shadow
                url={getPeopleThumbnailUrl(person)}
                altText={person.name}
                widthStyle="100%"
              />
              {#if person.isFavorite}
                <div class="absolute top-2 start-2">
                  <Icon path={mdiHeart} size="24" class="text-white" />
                </div>
              {/if}
              <p class="mt-2 text-ellipsis text-sm dark:text-white whitespace-nowrap overflow-hidden">
                {person.name.split(' ')[0]}
              </p>
            </a>
          {/each}
        {/snippet}
      </SingleGridRow>
    {:else}
      <EmptyPlaceholder text={$t('search_no_people')} src={emptyPeople} class="!mt-0" />
    {/if}
  </div>

  <div>
    <div class="flex justify-between py-8">
      <p class="font-medium dark:text-immich-dark-fg">{$t('places')}</p>
      <a
        href={resolve(AppRoute.PLACES)}
        class="pe-4 text-sm hover:text-immich-primary dark:text-immich-dark-fg dark:hover:text-immich-dark-primary"
        draggable="false"
      >
        {$t('view_all')}
      </a>
    </div>
    {#if places.length > 0}
      <SingleGridRow class="grid grid-flow-col md:auto-cols-[10rem] auto-cols-[6.625rem] md:gap-x-4 gap-x-[9px]">
        {#snippet children({ itemCount })}
          {#each places.slice(0, itemCount) as item (item.data.id)}
            <a
              class="relative md:w-40 w-26.5"
              href={resolve(`${AppRoute.SEARCH}?${getMetadataSearchQuery({ city: item.value })}`)}
              draggable="false"
            >
              <div class="flex justify-center overflow-hidden rounded-xl brightness-75 filter">
                <img
                  src={getAssetThumbnailUrl({ id: item.data.id, size: AssetMediaSize.Thumbnail })}
                  alt={item.value}
                  class="object-cover aspect-square w-full"
                />
              </div>
              <span
                class="w-100 absolute bottom-1 w-full px-1 text-center text-sm capitalize text-white hover:cursor-pointer whitespace-nowrap overflow-hidden text-ellipsis"
              >
                {item.value}
              </span>
            </a>
          {/each}
        {/snippet}
      </SingleGridRow>
    {:else}
      <EmptyPlaceholder text={$t('search_no_places')} src={emptyPlaces} class="!mt-0" />
    {/if}
  </div>
</UserPageLayout>
