<script lang="ts">
  import { goto } from '$app/navigation';
  import { page } from '$app/state';
  import empty1Url from '$lib/assets/empty-1.svg';
  import UserPageLayout from '$lib/components/layouts/UserPageLayout.svelte';
  import OnEvents from '$lib/components/OnEvents.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/EmptyPlaceholder.svelte';
  import SharedLinkCard from './SharedLinkCard.svelte';
  import { type SharedLinkTab } from '$lib/constants';
  import GroupTab from '$lib/elements/GroupTab.svelte';
  import { Route } from '$lib/route';
  import { locale } from '$lib/stores/preferences.store';
  import { formatPageTitleWithCount } from '$lib/utils/string-utils';
  import { getAllSharedLinks, SharedLinkType, type SharedLinkResponseDto } from '@immich/sdk';
  import { Container } from '@immich/ui';
  import { onMount, type Snippet } from 'svelte';
  import { t } from 'svelte-i18n';
  import type { LayoutData } from './$types';

  type Props = {
    children?: Snippet;
    data: LayoutData;
  };

  const { children, data }: Props = $props();

  let sharedLinks: SharedLinkResponseDto[] = $state([]);

  const refresh = async () => {
    sharedLinks = await getAllSharedLinks({});
  };

  onMount(async () => {
    await refresh();
  });

  const filterMap: Record<SharedLinkTab, string> = {
    all: $t('all'),
    album: $t('albums'),
    individual: $t('individual_shares'),
  };

  let filters = Object.keys(filterMap);
  let labels = Object.values(filterMap);

  const getActiveTab = (url: URL) => {
    const filter = url.searchParams.get('filter');
    return filter && filters.includes(filter) ? filter : 'all';
  };

  let selectedTab = $derived(getActiveTab(page.url));

  let filteredSharedLinks = $derived(
    sharedLinks.filter(
      ({ type }) =>
        selectedTab === 'all' ||
        (type === SharedLinkType.Album && selectedTab === 'album') ||
        (type === SharedLinkType.Individual && selectedTab === 'individual'),
    ),
  );

  const onSharedLinkUpdate = (sharedLink: SharedLinkResponseDto) => {
    const index = sharedLinks.findIndex((link) => link.id === sharedLink.id);
    if (index !== -1) {
      sharedLinks[index] = sharedLink;
    }
  };

  const onSharedLinkDelete = (sharedLink: SharedLinkResponseDto) => {
    sharedLinks = sharedLinks.filter(({ id }) => id !== sharedLink.id);
  };
</script>

<OnEvents {onSharedLinkUpdate} {onSharedLinkDelete} />

<UserPageLayout title={formatPageTitleWithCount(data.meta.title, filteredSharedLinks.length, $locale)}>
  {#snippet buttons()}
    <div class="hidden xl:block h-10">
      <GroupTab
        label={$t('show_shared_links')}
        {filters}
        {labels}
        selected={selectedTab}
        onSelect={(value) => goto(Route.sharedLinks({ filter: value as SharedLinkTab }))}
      />
    </div>
  {/snippet}

  <Container center size="medium">
    {#if sharedLinks.length === 0}
      <EmptyPlaceholder text={$t('you_dont_have_any_shared_links')} src={empty1Url} class="mx-auto mt-10" />
    {:else}
      <div class="flex flex-col gap-2">
        {#each filteredSharedLinks as sharedLink (sharedLink.id)}
          <SharedLinkCard {sharedLink} />
        {/each}
      </div>
    {/if}

    {@render children?.()}
  </Container>
</UserPageLayout>
