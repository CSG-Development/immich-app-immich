<script lang="ts">
  import { resolveRoute } from '$app/paths';
  import { focusOutside } from '$lib/actions/focus-outside';
  import Icon from '$lib/components/elements/icon.svelte';
  import ButtonContextMenu from '$lib/components/shared-components/context-menu/button-context-menu.svelte';
  import { AppRoute, QueryParameter } from '$lib/constants';
  import { getPeopleThumbnailUrl } from '$lib/utils';
  import { type PersonResponseDto } from '@immich/sdk';
  import {
    mdiAccountMultipleCheckOutline,
    mdiCalendarEditOutline,
    mdiDotsVertical,
    mdiEyeOffOutline,
    mdiHeart,
    mdiHeartMinusOutline,
    mdiHeartOutline,
  } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import ImageThumbnail from '../assets/thumbnail/image-thumbnail.svelte';
  import MenuOption from '../shared-components/context-menu/menu-option.svelte';

  interface Props {
    person: PersonResponseDto;
    onSetBirthDate: () => void;
    onMergePeople: () => void;
    onHidePerson: () => void;
    onToggleFavorite: () => void;
  }

  let { person, onSetBirthDate, onMergePeople, onHidePerson, onToggleFavorite }: Props = $props();

  let showVerticalDots = $state(false);
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
    href="{resolveRoute(AppRoute.PEOPLE, {})}/{person.id}?{QueryParameter.PREVIOUS_ROUTE}={resolveRoute(
      AppRoute.PEOPLE,
      {},
    )}"
    draggable="false"
    onfocus={() => (showVerticalDots = true)}
  >
    <div class="w-full h-full rounded-xl brightness-95 filter">
      <ImageThumbnail
        shadow
        url={getPeopleThumbnailUrl(person)}
        altText={person.name}
        title={person.name}
        widthStyle="100%"
        circle
      />
      {#if person.isFavorite}
        <div class="absolute top-4 start-4">
          <Icon path={mdiHeart} size="24" class="text-white" />
        </div>
      {/if}
    </div>
  </a>

  {#if showVerticalDots}
    <div class="absolute top-2 end-2 z-1">
      <ButtonContextMenu
        buttonClass="icon-white-drop-shadow focus:opacity-100 {showVerticalDots ? 'opacity-100' : 'opacity-0'}"
        color="primary"
        size="medium"
        icon={mdiDotsVertical}
        title={$t('show_person_options')}
      >
        <MenuOption onClick={onHidePerson} icon={mdiEyeOffOutline} text={$t('hide_person')} />
        <MenuOption onClick={onSetBirthDate} icon={mdiCalendarEditOutline} text={$t('set_date_of_birth')} />
        <MenuOption onClick={onMergePeople} icon={mdiAccountMultipleCheckOutline} text={$t('merge_people')} />
        <MenuOption
          onClick={onToggleFavorite}
          icon={person.isFavorite ? mdiHeartMinusOutline : mdiHeartOutline}
          text={person.isFavorite ? $t('unfavorite') : $t('to_favorite')}
        />
      </ButtonContextMenu>
    </div>
  {/if}
</div>
