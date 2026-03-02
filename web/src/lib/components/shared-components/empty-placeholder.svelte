<script lang="ts">
  import empty1Url from '$lib/assets/empty-1.svg';
  import { mobileDevice } from '$lib/stores/mobile-device.svelte';

  interface Props {
    onClick?: undefined | (() => unknown);
    text: string;
    fullWidth?: boolean;
    src?: string;
    title?: string;
    descriptionText?: string;
  }

  let { onClick = undefined, text, fullWidth = false, src = empty1Url, title, descriptionText = '' }: Props = $props();

  let width = $derived(fullWidth ? 'w-full' : mobileDevice.maxMd ? 'max-w-70' : 'w-130');

  const hoverClasses = onClick
    ? `border dark:border-immich-dark-gray hover:bg-immich-primary/5 dark:hover:bg-immich-dark-primary/25`
    : '';
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<svelte:element
  this={onClick ? 'button' : 'div'}
  onclick={onClick}
  class="{width} md:h-85 m-auto mt-10 flex flex-col place-content-center place-items-center gap-8 rounded-3xl bg-gray-50 p-5 dark:bg-immich-dark-gray-card {hoverClasses}"
>
  <img class="md:h-[200px] h-32" {src} alt="" draggable="false" />

  {#if title}
    <h2 class="text-xl font-medium my-4">{title}</h2>
  {/if}
  <span class="max-w-50 md:max-w-full pb-8 md:pb-0">
    <p class="text-immich-gray-text dark:text-immich-dark-gray-text font-medium text-center uppercase md:text-xl">
      {text}
    </p>
    {#if descriptionText}
      <p class="text-immich-gray-text dark:text-immich-dark-gray-text text-center text-xs md:text-base pt-1">
        {descriptionText}
      </p>
    {/if}
  </span>
</svelte:element>
