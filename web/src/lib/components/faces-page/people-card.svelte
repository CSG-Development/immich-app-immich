<script lang="ts" module>
  let openPersonId = $state<string | null>(null);
</script>

<script lang="ts">
  import { beforeNavigate } from '$app/navigation';
  import { clickOutside } from '$lib/actions/click-outside';
  import { focusOutside } from '$lib/actions/focus-outside';
  import { longPress } from '$lib/actions/long-press';
  import { portal } from '$lib/elements/Portal.svelte';
  import { Route } from '$lib/route';
  import { getPersonActions } from '$lib/services/person.service';
  import { getPeopleThumbnailUrl } from '$lib/utils';
  import { type PersonResponseDto } from '@immich/sdk';
  import { Icon, IconButton, type ActionItem } from '@immich/ui';
  import {
    mdiAccountMultipleCheckOutline,
    mdiDotsVertical,
    mdiEyeOffOutline,
    mdiHeart,
    mdiHeartMinusOutline,
    mdiHeartOutline,
  } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import { onDestroy, tick } from 'svelte';
  import { fly } from 'svelte/transition';
  import ImageThumbnail from '../assets/thumbnail/image-thumbnail.svelte';

  type Props = {
    person: PersonResponseDto;
    onMergePeople: () => void;
    onHidePerson: () => void;
    onToggleFavorite: () => void;
  };

  let { person, onMergePeople, onHidePerson, onToggleFavorite }: Props = $props();

  const MENU_MIN_WIDTH = 220;

  let showVerticalDots = $state(false);
  let menuPosition = $state({ left: 0, top: 0, maxHeight: undefined as number | undefined });
  let menuReady = $state(false);
  let menuElement: HTMLElement | undefined = $state();
  let triggerRect: DOMRect | undefined = $state();
  let cardElement: HTMLElement | undefined = $state();

  const menuOpen = $derived(openPersonId === person.id);

  // When another card opens its menu, hide this card's kebab (menu already closes via openPersonId).
  $effect(() => {
    if (openPersonId !== null && openPersonId !== person.id) {
      showVerticalDots = false;
      triggerRect = undefined;
      menuReady = false;
    }
  });

  const { SetDateOfBirth } = $derived(getPersonActions($t, person));

  const items = $derived(
    [
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
    ] satisfies ActionItem[],
  );

  const hideDots = () => {
    if (!menuOpen) {
      showVerticalDots = false;
    }
  };

  const closeMenu = () => {
    if (openPersonId === person.id) {
      openPersonId = null;
    }
    triggerRect = undefined;
    menuReady = false;
    hideDots();
  };

  // Body-portaled menus can be orphaned if the People page unmounts mid-outro
  // (portal + fly transition leaves the node on <body> after route change).
  // Always hard-remove the DOM node — clickOutside may already have cleared
  // openPersonId while the fly outro is still in progress.
  const dismissMenu = () => {
    const menu = menuElement;
    closeMenu();
    menu?.remove();
    menuElement = undefined;
  };

  beforeNavigate(dismissMenu);
  onDestroy(dismissMenu);

  const positionMenu = (anchor: DOMRect, menu: HTMLElement) => {
    const margin = 8;
    const gap = 4;

    // Measure unconstrained on <body> — parent card width must not affect this.
    menu.style.width = 'max-content';
    menu.style.minWidth = `${MENU_MIN_WIDTH}px`;

    const width = Math.max(menu.offsetWidth, MENU_MIN_WIDTH);
    const height = menu.offsetHeight || menu.scrollHeight;

    const spaceBelow = window.innerHeight - anchor.bottom - margin;
    const spaceAbove = anchor.top - margin;

    let top: number;
    let maxHeight: number | undefined;

    if (height <= spaceBelow) {
      top = anchor.bottom + gap;
    } else if (height <= spaceAbove) {
      top = anchor.top - height - gap;
    } else if (spaceBelow >= spaceAbove) {
      top = anchor.bottom + gap;
      maxHeight = Math.max(0, spaceBelow - gap);
    } else {
      maxHeight = Math.max(0, spaceAbove - gap);
      top = Math.max(margin, anchor.top - maxHeight - gap);
    }

    // Open to the right of the button; clamp if it would leave the viewport.
    let left = anchor.left;
    if (left + width > window.innerWidth - margin) {
      left = window.innerWidth - width - margin;
    }
    left = Math.max(margin, left);

    menuPosition = { left, top, maxHeight };
    menuReady = true;
  };

  const openMenuAt = (anchor: DOMRect, { toggle = false } = {}) => {
    if (menuOpen && toggle) {
      closeMenu();
      return;
    }

    if (menuOpen) {
      return;
    }

    triggerRect = anchor;
    menuPosition = { left: 0, top: 0, maxHeight: undefined };
    menuReady = false;
    openPersonId = person.id;
    showVerticalDots = true;
    window.getSelection()?.removeAllRanges();
  };

  const getMenuAnchor = () => {
    const button = cardElement?.querySelector<HTMLElement>('[aria-haspopup="menu"]');
    return button?.getBoundingClientRect() ?? cardElement?.getBoundingClientRect() ?? new DOMRect();
  };

  const openMenu = (event: MouseEvent) => {
    event.stopPropagation();
    event.preventDefault();
    openMenuAt((event.currentTarget as HTMLElement).getBoundingClientRect(), { toggle: true });
  };

  const openMenuFromGesture = () => {
    openMenuAt(getMenuAnchor());
  };

  const onContextMenu = (event: MouseEvent) => {
    event.preventDefault();
    event.stopPropagation();
    openMenuAt(new DOMRect(event.clientX, event.clientY, 0, 0));
  };

  $effect(() => {
    if (!menuOpen || !menuElement || !triggerRect) {
      return;
    }

    const anchor = triggerRect;
    const menu = menuElement;
    let cancelled = false;
    let frame = 0;

    void tick().then(() => {
      if (cancelled) {
        return;
      }

      frame = requestAnimationFrame(() => {
        if (!cancelled) {
          positionMenu(anchor, menu);
        }
      });
    });

    return () => {
      cancelled = true;
      cancelAnimationFrame(frame);
    };
  });

  const onSelect = (item: ActionItem) => {
    closeMenu();
    void item.onAction(item);
  };
</script>

<div
  bind:this={cardElement}
  id="people-card"
  class="relative"
  onmouseenter={() => (showVerticalDots = true)}
  onmouseleave={hideDots}
  oncontextmenu={onContextMenu}
  role="group"
  use:focusOutside={{ onFocusOut: hideDots }}
>
  <a
    href={Route.viewPerson(person, { previousRoute: Route.people() })}
    class="select-none"
    draggable="false"
    onfocus={() => (showVerticalDots = true)}
    use:longPress={{ onLongPress: openMenuFromGesture }}
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

  <div
    class="absolute top-2 end-2 z-1 transition-opacity {showVerticalDots || menuOpen
      ? 'opacity-100'
      : 'pointer-events-none opacity-0'}"
  >
    <IconButton
      class="icon-white-drop-shadow bg-black! text-white! hover:bg-black! not-disabled:hover:bg-black!"
      size="medium"
      icon={mdiDotsVertical}
      variant="ghost"
      shape="round"
      aria-label={$t('show_person_options')}
      aria-expanded={menuOpen}
      aria-haspopup="menu"
      tabindex={showVerticalDots || menuOpen ? undefined : -1}
      onmousedown={(event) => event.stopPropagation()}
      onclick={openMenu}
    />
  </div>
</div>

{#if menuOpen}
  <div
    bind:this={menuElement}
    class="fixed z-[9999] overflow-y-auto immich-scrollbar rounded-xl border border-immich-gray-border bg-immich-bg-gray-mt py-1 shadow-lg select-none dark:border-immich-dark-gray-border dark:bg-immich-dark-gray-card"
    class:invisible={!menuReady}
    style:left="{menuPosition.left}px"
    style:top="{menuPosition.top}px"
    style:max-height={menuPosition.maxHeight === undefined ? undefined : `${menuPosition.maxHeight}px`}
    role="menu"
    tabindex="-1"
    transition:fly={{ y: -8, duration: 150 }}
    use:portal
    use:clickOutside={{ onOutclick: closeMenu, onEscape: closeMenu }}
  >
    {#each items as item (item.title)}
      <button
        type="button"
        role="menuitem"
        class="flex w-full items-center gap-3 px-3 py-2 text-start text-sm whitespace-nowrap text-immich-fg hover:bg-immich-primary-12 dark:text-white/[.87] dark:hover:bg-immich-dark-primary-24"
        onclick={() => onSelect(item)}
      >
        {#if item.icon}
          <Icon icon={item.icon} size="20" class="shrink-0" />
        {/if}
        <span class="grow font-medium">{item.title}</span>
      </button>
    {/each}
  </div>
{/if}
