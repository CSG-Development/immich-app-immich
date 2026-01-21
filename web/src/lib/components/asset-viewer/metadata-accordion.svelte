<script lang="ts">
  import Icon from '$lib/components/elements/icon.svelte';
  import { getAccordionState } from '$lib/components/shared-components/settings/setting-accordion-state.svelte';
  import { onDestroy, onMount, type Snippet } from 'svelte';
  import { slide } from 'svelte/transition';

  const accordionState = getAccordionState();

  interface Props {
    title: string;
    key: string;
    isOpen?: boolean;
    autoScrollTo?: boolean;
    icon?: string;
    src?: string;
    length?: number;
    children?: Snippet;
  }

  let {
    title,
    key,
    isOpen = $bindable($accordionState.has(key)),
    autoScrollTo = false,
    icon = '',
    src = '',
    length = 0,
    children,
  }: Props = $props();

  let accordionElement: HTMLDivElement | undefined = $state();

  const setIsOpen = (isOpen: boolean) => {
    if (isOpen) {
      $accordionState = $accordionState.add(key);

      if (autoScrollTo) {
        setTimeout(() => {
          accordionElement?.scrollIntoView({
            behavior: 'smooth',
            block: 'start',
          });
        }, 200);
      }
    } else {
      $accordionState.delete(key);
      // eslint-disable-next-line no-self-assign
      $accordionState = $accordionState;
    }
  };

  onDestroy(() => {
    setIsOpen(false);
  });

  const onclick = () => {
    isOpen = !isOpen;
    setIsOpen(isOpen);
  };

  onMount(() => {
    setIsOpen(isOpen);
  });

  console.log(isOpen);
</script>

<div
  class="border-2 rounded-lg border-immich-gray-border dark:border-immich-dark-gray-border mb-4 px-4 py-6 transition-all {isOpen
    ? 'border-primary/60 dark:border-primary/60 shadow-md'
    : ''}"
  bind:this={accordionElement}
>
  <button
    type="button"
    aria-expanded={isOpen}
    {onclick}
    class="flex w-full place-items-center justify-between text-start"
  >
    <div>
      <div class="flex gap-2 place-items-center">
        {#if icon}
          <Icon path={icon} class="text-immich-primary dark:text-immich-dark-primary" size="24" ariaHidden />
        {/if}
        {#if src}
          <img class="text-primary" {src} alt="" />
        {/if}
        <h2 class="font-medium text-primary pl-2">
          {title}
        </h2>
        <div class="bg-immich-bg-gray-mt dark:bg-immich-dark-bg-gray-mt rounded-lg text-xs font-bold px-2 py-1">
          {length}
        </div>
      </div>
    </div>

    <div
      class="immich-circle-icon-button flex place-content-center place-items-center rounded-full transition-all hover:bg-immich-primary/10 dark:text-immich-dark-fg hover:dark:bg-immich-dark-primary/20"
    >
      <svg
        style="tran"
        width="20"
        height="20"
        fill="none"
        stroke-linecap="round"
        stroke-linejoin="round"
        stroke-width="2"
        viewBox="0 0 24 24"
        stroke="currentColor"
      >
        <path d="M19 9l-7 7-7-7" />
      </svg>
    </div>
  </button>

  {#if isOpen}
    <ul transition:slide={{ duration: 150 }} class="pb-2 pt-4 ps-4">
      {@render children?.()}
    </ul>
  {/if}
</div>

<style>
  svg {
    transition: transform 0.2s ease-in;
  }

  [aria-expanded='true'] svg {
    transform: rotate(0.5turn);
  }
</style>
