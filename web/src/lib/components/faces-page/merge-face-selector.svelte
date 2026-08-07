<script lang="ts">
  import { goto } from '$app/navigation';
  import { Route } from '$lib/route';
  import { handleError } from '$lib/utils/handle-error';
  import { getAllPeople, getPerson, mergePerson, type PersonResponseDto } from '@immich/sdk';
  import { Button, Icon, IconButton, modalManager, toastManager } from '@immich/ui';
  import { mdiCallMerge, mdiMerge, mdiSwapHorizontal } from '@mdi/js';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import { flip } from 'svelte/animate';
  import { quintOut } from 'svelte/easing';
  import { fly } from 'svelte/transition';
  import ControlAppBar from '../shared-components/control-app-bar.svelte';
  import FaceThumbnail from './face-thumbnail.svelte';
  import PeopleList from './people-list.svelte';

  interface Props {
    person: PersonResponseDto;
    onBack: () => void;
    onMerge: (mergedPerson: PersonResponseDto) => void;
  }

  let { person = $bindable(), onBack, onMerge }: Props = $props();

  let people: PersonResponseDto[] = $state([]);
  let selectedPeople: PersonResponseDto[] = $state([]);
  let screenHeight: number = $state(0);

  let hasSelection = $derived(selectedPeople.length > 0);
  let peopleToNotShow = $derived([...selectedPeople, person]);

  const handleSearch = async (sortFaces: boolean = false) => {
    const data = await getAllPeople({ withHidden: false, closestPersonId: sortFaces ? person.id : undefined });
    people = data.people;
  };

  onMount(handleSearch);

  const handleSwapPeople = async () => {
    const previousPerson = person;
    const [newTarget, ...rest] = selectedPeople;
    selectedPeople = [previousPerson, ...rest];
    person = newTarget;
    await goto(Route.viewPerson(person, { previousRoute: Route.people(), action: 'merge' }));
  };

  const onSelect = async (selected: PersonResponseDto) => {
    if (selectedPeople.includes(selected)) {
      selectedPeople = selectedPeople.filter((person) => person.id !== selected.id);
      return;
    }

    if (selectedPeople.length >= 5) {
      toastManager.warning($t('merge_people_limit'));
      return;
    }

    selectedPeople = [selected, ...selectedPeople];

    if (selectedPeople.length === 1 && !person.name && selected.name) {
      await handleSwapPeople();
    }
  };

  const handleMerge = async () => {
    const isConfirm = await modalManager.showDialog({ prompt: $t('merge_people_prompt') });
    if (!isConfirm) {
      return;
    }

    try {
      let results = await mergePerson({
        id: person.id,
        mergePersonDto: { ids: selectedPeople.map(({ id }) => id) },
      });
      const mergedPerson = await getPerson({ id: person.id });
      const count = results.filter(({ success }) => success).length;
      toastManager.primary($t('merged_people_count', { values: { count } }));
      onMerge(mergedPerson);
    } catch (error) {
      handleError(error, $t('cannot_merge_people'));
    }
  };
</script>

<svelte:window bind:innerHeight={screenHeight} />

<section
  transition:fly={{ y: 500, duration: 100, easing: quintOut }}
  class="absolute start-0 top-0 h-full w-full bg-bg"
>
  <ControlAppBar onClose={onBack}>
    {#snippet leading()}
      {#if hasSelection}
        {$t('selected_count', { values: { count: selectedPeople.length } })}
      {:else}
        {$t('merge_people')}
      {/if}
      <div></div>
    {/snippet}
    {#snippet trailing()}
      <Button
        leadingIcon={mdiMerge}
        size="small"
        shape="round"
        disabled={!hasSelection}
        onclick={handleMerge}
        class="[&_svg]:rotate-90 h-11.5 text-sm gap-2"
      >
        {$t('merge')}
      </Button>
    {/snippet}
  </ControlAppBar>
  <section class="px-3 md:px-6 pt-[100px]">
    <section id="merge-face-selector">
      <div class="mb-3 h-50 place-content-center place-items-center">
        <p class="mb-4 text-center uppercase text-immich-gray-text dark:text-immich-dark-gray-text md:font-medium">
          {$t('choose_matching_people_to_merge')}
        </p>

        <div
          class="overflow-x-auto grid grid-flow-col-dense place-content-center place-items-center w-full gap-3 md:gap-4"
        >
          {#each selectedPeople as selectedPerson (selectedPerson.id)}
            <div animate:flip={{ duration: 250, easing: quintOut }}>
              <FaceThumbnail
                border
                circle
                person={selectedPerson}
                selectable
                thumbnailSize={117}
                onClick={() => onSelect(selectedPerson)}
              />
            </div>
          {/each}

          {#if hasSelection}
            <div class="relative">
              <div class="flex flex-col h-full justify-between">
                <div class="flex h-full items-center justify-center">
                  <Icon icon={mdiCallMerge} size="48" class="rotate-90 dark:text-white" />
                </div>
                {#if selectedPeople.length === 1}
                  <IconButton
                    shape="round"
                    color="secondary"
                    variant="ghost"
                    aria-label={$t('swap_merge_direction')}
                    icon={mdiSwapHorizontal}
                    size="medium"
                    onclick={handleSwapPeople}
                  />
                {/if}
              </div>
            </div>
          {/if}
          {#key person.id}
            <FaceThumbnail {person} border circle selectable={false} thumbnailSize={156} />
          {/key}
        </div>
      </div>
      <PeopleList {people} {peopleToNotShow} {screenHeight} {onSelect} {handleSearch} />
    </section>
  </section>
</section>
