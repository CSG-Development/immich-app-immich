<script lang="ts">
  import emptyPeople from '$lib/assets/empty-people.svg';
  import emptyPlaces from '$lib/assets/empty-places.svg';
  import ImageThumbnail from '$lib/components/assets/thumbnail/image-thumbnail.svelte';
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import OnEvents from '$lib/components/OnEvents.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/empty-placeholder.svelte';
  import SingleGridRow from '$lib/components/shared-components/single-grid-row.svelte';
  import { Route } from '$lib/route';
  import { getAssetMediaUrl, getPeopleThumbnailUrl } from '$lib/utils';
  import { AssetMediaSize, type SearchExploreResponseDto } from '@immich/sdk';
  import { Icon } from '@immich/ui';
  import { mdiHeart } from '@mdi/js';
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

  const onPersonThumbnailReady = ({ id }: { id: string }) => {
    for (const person of people) {
      if (person.id === id) {
        person.updatedAt = new Date().toISOString();
      }
    }
  };
</script>

<OnEvents {onPersonThumbnailReady} />

<UserPageLayout title={data.meta.title}>
  <div class="mt-2">
    <div class="flex justify-between pt-6 pb-8">
      <p class="font-medium dark:text-immich-dark-fg">{$t('people')}</p>
      <a
        href={Route.people()}
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
            <a href={Route.viewPerson(person)} class="text-center relative">
              <ImageThumbnail
                circle
                shadow
                url={getPeopleThumbnailUrl(person)}
                altText={person.name}
                widthStyle="100%"
              />
              {#if person.isFavorite}
                <div class="absolute top-2 start-2">
                  <Icon icon={mdiHeart} size="24" class="text-white" />
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
        href={Route.places()}
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
            <a class="relative md:w-40 w-26.5" href={Route.search({ city: item.value })} draggable="false">
              <div class="flex justify-center overflow-hidden rounded-xl brightness-75 filter">
                <img
                  src={getAssetMediaUrl({ id: item.data.id, size: AssetMediaSize.Thumbnail })}
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
