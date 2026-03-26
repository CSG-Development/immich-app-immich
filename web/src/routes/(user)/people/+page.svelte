<script lang="ts">
  import { goto } from '$app/navigation';
  import { resolve } from '$app/paths';
  import { page } from '$app/state';
  import { focusTrap } from '$lib/actions/focus-trap';
  import { scrollMemory } from '$lib/actions/scroll-memory';
  import { shortcut } from '$lib/actions/shortcut';
  import emptyPeople from '$lib/assets/empty-people.svg';
  import ManagePeopleVisibility from '$lib/components/faces-page/manage-people-visibility.svelte';
  import PeopleCard from '$lib/components/faces-page/people-card.svelte';
  import PeopleInfiniteScroll from '$lib/components/faces-page/people-infinite-scroll.svelte';
  import SearchPeople from '$lib/components/faces-page/people-search.svelte';
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/empty-placeholder.svelte';
  import {
    notificationController,
    NotificationType,
  } from '$lib/components/shared-components/notification/notification';
  import { ActionQueryParameterValue, AppRoute, QueryParameter, SessionStorageKey } from '$lib/constants';
  import { modalManager } from '$lib/managers/modal-manager.svelte';
  import PersonEditBirthDateModal from '$lib/modals/PersonEditBirthDateModal.svelte';
  import PersonMergeSuggestionModal from '$lib/modals/PersonMergeSuggestionModal.svelte';
  import { mobileDevice } from '$lib/stores/mobile-device.svelte';
  import { locale } from '$lib/stores/preferences.store';
  import { websocketEvents } from '$lib/stores/websocket';
  import { handlePromiseError } from '$lib/utils';
  import { handleError } from '$lib/utils/handle-error';
  import { clearQueryParam } from '$lib/utils/navigation';
  import { getAllPeople, getPerson, searchPerson, updatePerson, type PersonResponseDto } from '@immich/sdk';
  import { Button } from '@immich/ui';
  import { mdiEyeOutline } from '@mdi/js';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import { quintOut } from 'svelte/easing';
  import { fly } from 'svelte/transition';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  let selectHidden = $state(false);
  let searchName = $state('');
  let newName = $state('');
  let currentPage = $state(1);
  let nextPage = $state(data.people.hasNextPage ? 2 : null);
  let personMerge1 = $state<PersonResponseDto>();
  let personMerge2 = $state<PersonResponseDto>();
  let potentialMergePeople: PersonResponseDto[] = $state([]);
  let editingPerson: PersonResponseDto | null = $state(null);
  let searchedPeopleLocal: PersonResponseDto[] = $state([]);
  let innerHeight = $state(0);
  let searchPeopleElement = $state<ReturnType<typeof SearchPeople>>();

  onMount(() => {
    const getSearchedPeople = page.url.searchParams.get(QueryParameter.SEARCHED_PEOPLE);
    if (getSearchedPeople) {
      searchName = getSearchedPeople;
      if (searchPeopleElement) {
        handlePromiseError(searchPeopleElement.searchPeople(true, searchName));
      }
    }

    return websocketEvents.on('on_person_thumbnail', (personId: string) => {
      for (const person of people) {
        if (person.id === personId) {
          person.updatedAt = new Date().toISOString();
        }
      }
    });
  });

  const loadInitialScroll = () =>
    new Promise<void>((resolve) => {
      // Load up to previously loaded page when returning.
      let newNextPage = sessionStorage.getItem(SessionStorageKey.INFINITE_SCROLL_PAGE);
      if (newNextPage && nextPage) {
        let startingPage = nextPage,
          pagesToLoad = Number.parseInt(newNextPage) - nextPage;

        if (pagesToLoad) {
          handlePromiseError(
            Promise.all(
              Array.from({ length: pagesToLoad }).map((_, i) => {
                return getAllPeople({ withHidden: true, page: startingPage + i });
              }),
            ).then((pages) => {
              for (const page of pages) {
                people = people.concat(page.people);
              }
              currentPage = startingPage + pagesToLoad - 1;
              nextPage = pages.at(-1)?.hasNextPage ? startingPage + pagesToLoad : null;
              resolve(); // wait until extra pages are loaded
            }),
          );
        } else {
          resolve();
        }
        sessionStorage.removeItem(SessionStorageKey.INFINITE_SCROLL_PAGE);
      }
    });

  const loadNextPage = async () => {
    if (!nextPage) {
      return;
    }

    try {
      const { people: newPeople, hasNextPage } = await getAllPeople({ withHidden: true, page: nextPage });
      people = people.concat(newPeople);
      if (nextPage !== null) {
        currentPage = nextPage;
      }
      nextPage = hasNextPage ? nextPage + 1 : null;
    } catch (error) {
      handleError(error, $t('errors.failed_to_load_people'));
    }
  };

  const handleSearch = async () => {
    const getSearchedPeople = page.url.searchParams.get(QueryParameter.SEARCHED_PEOPLE);
    if (getSearchedPeople !== searchName) {
      page.url.searchParams.set(QueryParameter.SEARCHED_PEOPLE, searchName);
      await goto(page.url, { keepFocus: true });
    }
  };

  const handleMerge = async () => {
    if (!editingPerson || !personMerge1 || !personMerge2) {
      return;
    }

    const response = await modalManager.show(PersonMergeSuggestionModal, {
      personToMerge: personMerge1,
      personToBeMergedInto: personMerge2,
      potentialMergePeople,
    });

    if (!response) {
      await updateName(personMerge1.id, newName);
      return;
    }

    const [personToMerge, personToBeMergedInto] = response;

    const mergedPerson = await getPerson({ id: personToBeMergedInto.id });

    people = people.filter((person: PersonResponseDto) => person.id !== personToMerge.id);
    people = people.map((person: PersonResponseDto) => (person.id === personToBeMergedInto.id ? mergedPerson : person));

    if (personToBeMergedInto.name !== newName && editingPerson.id === personToBeMergedInto.id) {
      /*
       *
       * If the user merges one of the suggested people into the person he's editing, it's merging the suggested person AND renames
       * the person he's editing
       *
       */
      try {
        await updatePerson({ id: personToBeMergedInto.id, personUpdateDto: { name: newName } });

        for (const person of people) {
          if (person.id === personToBeMergedInto.id) {
            person.name = newName;
            break;
          }
        }
        notificationController.show({
          message: $t('change_name_successfully'),
          type: NotificationType.Success,
        });
      } catch (error) {
        handleError(error, $t('errors.unable_to_save_name'));
      }
    }
  };

  const handleHidePerson = async (detail: PersonResponseDto) => {
    try {
      const updatedPerson = await updatePerson({
        id: detail.id,
        personUpdateDto: { isHidden: true },
      });

      people = people.map((person: PersonResponseDto) => {
        if (person.id === updatedPerson.id) {
          return updatedPerson;
        }
        return person;
      });

      notificationController.show({
        message: $t('changed_visibility_successfully'),
        type: NotificationType.Success,
      });
    } catch (error) {
      handleError(error, $t('errors.unable_to_hide_person'));
    }
  };

  const handleToggleFavorite = async (detail: PersonResponseDto) => {
    try {
      const updatedPerson = await updatePerson({
        id: detail.id,
        personUpdateDto: { isFavorite: !detail.isFavorite },
      });

      people = people.map((person: PersonResponseDto) => {
        if (person.id === updatedPerson.id) {
          return updatedPerson;
        }
        return person;
      });

      notificationController.show({
        message: updatedPerson.isFavorite ? $t('added_to_favorites') : $t('removed_from_favorites'),
        type: NotificationType.Success,
      });
    } catch (error) {
      handleError(error, $t('errors.unable_to_add_remove_favorites', { values: { favorite: detail.isFavorite } }));
    }
  };

  const handleMergePeople = async (detail: PersonResponseDto) => {
    await goto(
      `${resolve(AppRoute.PEOPLE)}/${detail.id}?${QueryParameter.ACTION}=${ActionQueryParameterValue.MERGE}&${QueryParameter.PREVIOUS_ROUTE}=${resolve(AppRoute.PEOPLE)}`,
    );
  };

  const handleChangeBirthDate = async (person: PersonResponseDto) => {
    const updatedPerson = await modalManager.show(PersonEditBirthDateModal, { person });

    if (!updatedPerson) {
      return;
    }

    people = people.map((person: PersonResponseDto) => {
      if (person.id === updatedPerson.id) {
        return updatedPerson;
      }
      return person;
    });
  };

  const onResetSearchBar = async () => {
    await clearQueryParam(QueryParameter.SEARCHED_PEOPLE, page.url);
  };

  let people = $state(data.people.people);
  let totalPeople = $derived(people.length);
  let hiddenCount = $derived(people.filter((p) => p.isHidden).length);
  let visiblePeople = $derived(people.filter((people) => !people.isHidden));
  let countVisiblePeople = $derived(searchName ? searchedPeopleLocal.length : totalPeople - hiddenCount);
  let showPeople = $derived(searchName ? searchedPeopleLocal : visiblePeople);

  const onNameChangeInputFocus = (person: PersonResponseDto) => {
    editingPerson = person;
    newName = person.name;
  };

  const onNameChangeSubmit = async (name: string, targetPerson: PersonResponseDto) => {
    try {
      if (name == targetPerson.name) {
        return;
      }

      if (name === '') {
        await updateName(targetPerson.id, '');
        return;
      }

      const personWithSimilarName = await findPeopleWithSimilarName(name, targetPerson.id);
      if (personWithSimilarName) {
        personMerge1 = targetPerson;
        personMerge2 = personWithSimilarName;
        potentialMergePeople = people
          .filter(
            (person: PersonResponseDto) =>
              personMerge2?.name.toLowerCase() === person.name.toLowerCase() &&
              person.id !== personMerge2.id &&
              person.id !== personMerge1?.id &&
              !person.isHidden,
          )
          .slice(0, 3);
        await handleMerge();
        return;
      }
      await updateName(targetPerson.id, name);
    } catch (error) {
      handleError(error, $t('errors.unable_to_save_name'));
    }
  };

  const onNameChangeInputUpdate = (event: Event) => {
    if (event.target) {
      newName = (event.target as HTMLInputElement).value;
    }
  };

  const updateName = async (id: string, name: string) => {
    await updatePerson({
      id,
      personUpdateDto: { name },
    });

    newName = '';
  };

  const findPeopleWithSimilarName = async (name: string, personId: string) => {
    const searchResult = await searchPerson({ name, withHidden: true });
    return searchResult.find(
      (person) => person.name.toLowerCase() === name.toLowerCase() && person.id !== personId && person.name,
    );
  };

  const refreshPeople = async () => {
    const result = await getAllPeople({ withHidden: true });
    people = result.people;
  };
</script>

<svelte:window bind:innerHeight />

<UserPageLayout
  title={$t('people')}
  description={countVisiblePeople === 0 && !searchName
    ? undefined
    : $t('items_count', { values: { count: countVisiblePeople.toLocaleString($locale) } })}
  use={[
    [
      scrollMemory,
      {
        routeStartsWith: AppRoute.PEOPLE,
        beforeSave: () => {
          if (currentPage) {
            sessionStorage.setItem(SessionStorageKey.INFINITE_SCROLL_PAGE, currentPage.toString());
          }
        },
        beforeClear: () => {
          sessionStorage.removeItem(SessionStorageKey.INFINITE_SCROLL_PAGE);
        },
        beforeLoad: loadInitialScroll,
      },
    ],
  ]}
>
  {#snippet buttons()}
    {#if people.length > 0}
      <div class="flex gap-2 items-center justify-center">
        <div class="hidden sm:block">
          <div class="w-full md:w-55 h-10">
            <SearchPeople
              bind:this={searchPeopleElement}
              type="searchBar"
              placeholder={$t('search_people')}
              onReset={onResetSearchBar}
              onSearch={handleSearch}
              bind:searchName
              bind:searchedPeopleLocal
            />
          </div>
        </div>
        <Button
          leadingIcon={mdiEyeOutline}
          onclick={() => (selectHidden = !selectHidden)}
          size="small"
          variant="ghost"
          color="secondary"
          shape="round"
          class="px-0 md:px-4"
        >
          {$t('show_and_hide_people')}
        </Button>
      </div>
    {/if}
  {/snippet}

  {#if mobileDevice.maxMd}
    <div class="h-10 my-2">
      <SearchPeople
        bind:this={searchPeopleElement}
        type="searchBar"
        placeholder={$t('search_people')}
        onReset={onResetSearchBar}
        onSearch={handleSearch}
        bind:searchName
        bind:searchedPeopleLocal
      />
    </div>
  {/if}

  {#if countVisiblePeople > 0 && (!searchName || searchedPeopleLocal.length > 0)}
    <PeopleInfiniteScroll people={showPeople} hasNextPage={!!nextPage && !searchName} {loadNextPage}>
      {#snippet children({ person })}
        <div
          class="pt-1 flex flex-col items-center w-41 h-50 rounded-xl border border-transparent hover:border-primary hover:bg-immich-bg-gray"
        >
          <PeopleCard
            {person}
            onSetBirthDate={() => handleChangeBirthDate(person)}
            onMergePeople={() => handleMergePeople(person)}
            onHidePerson={() => handleHidePerson(person)}
            onToggleFavorite={() => handleToggleFavorite(person)}
          />

          <input
            type="text"
            class="placeholder-immich-gray-text dark:placeholder-immich-dark-gray-text text-center w-full md:w-39 mt-2 py-1 text-sm text-immich-primary dark:text-immich-dark-primary rounded-[28px] hover:bg-white dark:hover:bg-immich-dark-gray-card focus:bg-white"
            value={person.name}
            placeholder={$t('add_a_name')}
            use:shortcut={{ shortcut: { key: 'Enter' }, onShortcut: (e) => e.currentTarget.blur() }}
            onfocusin={() => onNameChangeInputFocus(person)}
            onfocusout={() => onNameChangeSubmit(newName, person)}
            oninput={(event) => onNameChangeInputUpdate(event)}
          />
        </div>
      {/snippet}
    </PeopleInfiniteScroll>
  {:else}
    <EmptyPlaceholder
      text={$t(searchName ? 'search_no_people_named' : 'search_no_people', { values: { name: searchName } })}
      src={emptyPeople}
    />
  {/if}
</UserPageLayout>

{#if selectHidden}
  <dialog
    open
    transition:fly={{ y: innerHeight, duration: 150, easing: quintOut, opacity: 0 }}
    class="absolute start-0 top-0 h-full w-full bg-bg"
    aria-modal="true"
    aria-labelledby="manage-visibility-title"
    use:focusTrap
  >
    <ManagePeopleVisibility
      bind:people
      totalPeopleCount={totalPeople}
      titleId="manage-visibility-title"
      onClose={() => (selectHidden = false)}
      {loadNextPage}
    />
  </dialog>
{/if}
