<script lang="ts">
  import { focusOutside } from '$lib/actions/focus-outside';
  import { Route } from '$lib/route';
  import { getPersonActions } from '$lib/services/person.service';
  import { getPeopleThumbnailUrl } from '$lib/utils';
  import { type PersonResponseDto } from '@immich/sdk';
  import { ContextMenuButton, Icon, type ActionItem } from '@immich/ui';
  import {
    mdiAccountMultipleCheckOutline,
    mdiDotsVertical,
    mdiEyeOffOutline,
    mdiHeart,
    mdiHeartMinusOutline,
    mdiHeartOutline,
  } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import ImageThumbnail from '../assets/thumbnail/image-thumbnail.svelte';

  type Props = {
    person: PersonResponseDto;
    onMergePeople: () => void;
    onHidePerson: () => void;
    onToggleFavorite: () => void;
  };

  let { person, onMergePeople, onHidePerson, onToggleFavorite }: Props = $props();

  let showVerticalDots = $state(false);

  const { SetDateOfBirth } = $derived(getPersonActions($t, person));

  const items = $derived([
    {
      title: $t('hide_person'),
      icon: mdiEyeOffOutline,
      onAction: onHidePerson,
    },
    SetDateOfBirth,
    {
      title: $t('merge_people'),
      icon: mdiAccountMultipleCheckOutline,
      onAction: onMergePeople,
    },
    {
      title: person.isFavorite ? $t('unfavorite') : $t('to_favorite'),
      icon: person.isFavorite ? mdiHeartMinusOutline : mdiHeartOutline,
      onAction: onToggleFavorite,
    },
  ] satisfies ActionItem[]);
</script>

<div
  id="people-card"
  class="relative"
  onmouseenter={() => (showVerticalDots = true)}
  onmouseleave={() => (showVerticalDots = false)}
  role="group"
  use:focusOutside={{ onFocusOut: () => (showVerticalDots = false) }}
>
  <a
    href={Route.viewPerson(person, { previousRoute: Route.people() })}
    draggable="false"
    onfocus={() => (showVerticalDots = true)}
  >
    <div class="w-39 h-full rounded-xl brightness-95 filter">
      <ImageThumbnail
        shadow
        url={getPeopleThumbnailUrl(person)}
        altText={person.name}
        title={person.name}
        widthStyle="100%"
        circle
        preload={false}
      />
      {#if person.isFavorite}
        <div class="absolute top-4 start-4">
          <Icon icon={mdiHeart} size="24" class="text-white" />
        </div>
      {/if}
    </div>
  </a>

  {#if showVerticalDots}
    <div class="absolute top-2 end-2 z-1 bg-black rounded-full">
      <ContextMenuButton
        class="icon-white-drop-shadow focus:opacity-100 text-white {showVerticalDots ? 'opacity-100' : 'opacity-0'}"
        size="medium"
        icon={mdiDotsVertical}
        aria-label={$t('show_person_options')}
        {items}
      />
    </div>
  {/if}
</div>
