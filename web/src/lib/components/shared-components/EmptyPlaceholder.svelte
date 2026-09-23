<script lang="ts">
  import empty1Url from '$lib/assets/empty-1.svg';
  import { mobileDevice } from '$lib/stores/mobile-device.svelte';

  interface Props {
    onClick?: undefined | (() => unknown);
    text: string;
    fullWidth?: boolean;
    src?: string;
    descriptionText?: string;
    title?: string;
    class?: string;
    truncate?: boolean;
  }

  let {
    onClick = undefined,
    text,
    fullWidth = false,
    src = empty1Url,
    title,
    descriptionText = '',
    class: className = '',
    truncate = false,
  }: Props = $props();

  let width = $derived(fullWidth ? 'w-full' : mobileDevice.maxMd ? 'max-w-70' : 'w-130');

  const hoverClasses = onClick
    ? `border dark:border-immich-dark-gray hover:bg-immich-primary/5 dark:hover:bg-immich-dark-primary/25`
    : '';
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<svelte:element
  this={onClick ? 'button' : 'div'}
  onclick={onClick}
  class="{width} md:min-h-85 m-auto mt-10 flex flex-col place-content-center place-items-center gap-6 rounded-3xl bg-gray-50 p-8 dark:bg-immich-dark-gray-card {hoverClasses} {className}"
>
  <img class="md:h-[200px] h-32 shrink-0" {src} alt="" draggable="false" />

  <div class="flex w-full max-w-xl flex-col items-center gap-2 px-2">
    {#if title}
      <h2 class="text-center text-xl font-medium text-immich-fg dark:text-immich-dark-fg">{title}</h2>
    {/if}
    <p
      class="text-immich-gray-text dark:text-immich-dark-gray-text text-center md:text-xl {truncate ? 'truncate' : ''}"
    >
      {text}
    </p>
    {#if descriptionText}
      <p class="text-immich-gray-text dark:text-immich-dark-gray-text text-center text-xs md:text-base">
        {descriptionText}
      </p>
    {/if}
  </div>
</svelte:element>
