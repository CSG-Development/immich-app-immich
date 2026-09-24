<script lang="ts">
  import emptyPeople from '$lib/assets/empty-people.svg';
  import emptyPlaces from '$lib/assets/empty-places.svg';
  import ImageThumbnail from '$lib/components/assets/thumbnail/ImageThumbnail.svelte';
  import UserPageLayout from '$lib/components/layouts/UserPageLayout.svelte';
  import OnEvents from '$lib/components/OnEvents.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/EmptyPlaceholder.svelte';
  import SingleGridRow from '$lib/components/shared-components/SingleGridRow.svelte';
  import Portal from '$lib/elements/Portal.svelte';
  import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { Route } from '$lib/route';
  import { getAssetMediaUrl, getPeopleThumbnailUrl } from '$lib/utils';
  import { getAltText } from '$lib/utils/thumbnail-util';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import { AssetMediaSize, getAssetInfo, type SearchExploreResponseDto } from '@immich/sdk';
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
  let recents = $derived(
    getFieldItems(data.items, 'createdAt').sort((a, b) => new Date(b.value).getTime() - new Date(a.value).getTime()),
  );
  let people = $state(data.response.people);

  let hasPeople = $derived(data.response.total > 0);

  const onPersonThumbnailReady = ({ id }: { id: string }) => {
    for (const person of people) {
      if (person.id === id) {
        person.updatedAt = new Date().toISOString();
      }
    }
  };

  const onViewAsset = async (id: string) => {
    const asset = await getAssetInfo({ ...authManager.params, id });
    assetViewerManager.setAsset(asset);
  };

  const assetCursor = $derived({
    current: assetViewerManager.asset!,
  });
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

  {#if recents.length > 0}
    <div class="mt-2 mb-6">
      <div class="flex justify-between py-8">
        <p class="font-medium dark:text-immich-dark-fg">{$t('recently_added')}</p>
        <a
          href={Route.recentlyAdded()}
          class="pe-4 text-sm hover:text-immich-primary dark:text-immich-dark-fg dark:hover:text-immich-dark-primary"
          draggable="false"
        >
          {$t('view_all')}
        </a>
      </div>
      <div class="flex h-24 max-w-fit flex-wrap gap-x-1 overflow-hidden md:h-42">
        {#each recents as item (item.data.id)}
          <button
            type="button"
            class="relative h-full flex-auto"
            onclick={() => onViewAsset(item.data.id)}
            draggable="false"
          >
            <img
              src={getAssetMediaUrl({ id: item.data.id, size: AssetMediaSize.Thumbnail })}
              alt={$getAltText(toTimelineAsset(item.data))}
              class="size-full min-w-max rounded-xl object-cover"
            />
          </button>
        {/each}
      </div>
    </div>
  {/if}
</UserPageLayout>

{#if assetViewerManager.isViewing}
  {#await import('$lib/components/asset-viewer/AssetViewer.svelte') then { default: AssetViewer }}
    <Portal target="body">
      <AssetViewer
        cursor={assetCursor}
        showNavigation={false}
        onClose={() => assetViewerManager.showAssetViewer(false)}
      />
    </Portal>
  {/await}
{/if}
