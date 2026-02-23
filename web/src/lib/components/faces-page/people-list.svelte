<script lang="ts">
  import SearchPeople from '$lib/components/faces-page/people-search.svelte';
  import { mobileDevice } from '$lib/stores/mobile-device.svelte';
  import { type PersonResponseDto } from '@immich/sdk';
  import { IconButton } from '@immich/ui';
  import { mdiSwapVertical } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import FaceThumbnail from './face-thumbnail.svelte';

  interface Props {
    screenHeight: number;
    people: PersonResponseDto[];
    peopleToNotShow: PersonResponseDto[];
    onSelect: (person: PersonResponseDto) => void;
    handleSearch?: (sortFaces: boolean) => void;
  }

  let { screenHeight, people, peopleToNotShow, onSelect, handleSearch }: Props = $props();
  let searchedPeopleLocal: PersonResponseDto[] = $state([]);
  let sortBySimilarirty = $state(false);
  let name = $state('');

  const showPeople = $derived(
    (name ? searchedPeopleLocal : people).filter(
      (person) => !peopleToNotShow.some((unselectedPerson) => unselectedPerson.id === person.id),
    ),
  );
</script>

<div class="w-full md:w-155.5 h-13 md:h-15.5 flex gap-4 place-items-center justifiy-between">
  <div class="w-full h-full">
    <SearchPeople type="searchBar" placeholder={$t('search_people')} bind:searchName={name} bind:searchedPeopleLocal />
  </div>

  {#if handleSearch}
    <IconButton
      shape="round"
      color="secondary"
      variant="ghost"
      icon={mdiSwapVertical}
      onclick={() => {
        sortBySimilarirty = !sortBySimilarirty;
        handleSearch(sortBySimilarirty);
      }}
      aria-label={$t('sort_people_by_similarity')}
      size="medium"
    />
  {/if}
</div>

{#if showPeople.length > 0}
  <div class="overflow-y-hidden rounded-3xl bg-light dark:bg-immich-dark-gray-card mt-6 border immich-border">
    <div class="overflow-y-auto p-8">
      <div
        class="grid gap-[33px] justify-between"
        style="grid-template-columns: repeat(auto-fill, 117px);"
        style:max-height={mobileDevice.maxMd ? screenHeight - 464 + 'px' : 117 * 3 + 65 + 'px'}
      >
        {#each showPeople as person (person.id)}
          <FaceThumbnail {person} onClick={() => onSelect(person)} circle border selectable thumbnailSize={117} />
        {/each}
      </div>
    </div>
  </div>
{/if}
