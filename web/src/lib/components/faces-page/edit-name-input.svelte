<script lang="ts">
  import SearchPeople from '$lib/components/faces-page/people-search.svelte';
  import { type PersonResponseDto } from '@immich/sdk';
  import { Button } from '@immich/ui';
  import { t } from 'svelte-i18n';
  import ImageThumbnail from '../assets/thumbnail/image-thumbnail.svelte';

  interface Props {
    person: PersonResponseDto;
    name: string;
    suggestedPeople: PersonResponseDto[];
    thumbnailData: string;
    isSearchingPeople: boolean;
    onChange: (name: string) => void;
  }

  let {
    person,
    name = $bindable(),
    suggestedPeople = $bindable(),
    thumbnailData,
    isSearchingPeople = $bindable(),
    onChange,
  }: Props = $props();

  const onsubmit = (event: Event) => {
    event.preventDefault();
    onChange(name);
  };
</script>

<div
  class="flex w-60 h-20 place-items-center {suggestedPeople.length > 0
    ? 'rounded-t-xl'
    : 'rounded-xl'} p-2 bg-light dark:bg-immich-dark-gray-card border immich-border"
>
  <ImageThumbnail circle shadow url={thumbnailData} altText={person.name} widthStyle="2.5rem" heightStyle="2.5rem" />
  <form class="ms-3 flex w-full justify-between gap-3" autocomplete="off" {onsubmit}>
    <SearchPeople
      bind:searchName={name}
      bind:searchedPeopleLocal={suggestedPeople}
      type="input"
      numberPeopleToSearch={5}
      inputClass="w-full font-bold gap-2 bg-white text-primary"
      bind:showLoadingSpinner={isSearchingPeople}
    />
    <Button class="rounded-3xl w-16.25 h-7 font-normal text-sm" type="submit">{$t('done')}</Button>
  </form>
</div>
