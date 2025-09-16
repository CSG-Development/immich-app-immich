<script lang="ts">
  import empty1Url from '$lib/assets/empty-1.svg';
  import { mobileDevice } from '$lib/stores/mobile-device.svelte';

  interface Props {
    onClick?: undefined | (() => unknown);
    text: string;
    fullWidth?: boolean;
    src?: string;
    title?: string;
  }

  let { onClick = undefined, text, fullWidth = false, src = empty1Url, title }: Props = $props();

  let width = $derived(fullWidth || mobileDevice.maxMd ? 'w-full' : 'w-130');

  const hoverClasses = onClick
    ? `border dark:border-immich-dark-gray hover:bg-immich-primary/5 dark:hover:bg-immich-dark-primary/25`
    : '';
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<svelte:element
  this={onClick ? 'button' : 'div'}
  onclick={onClick}
  class="{width} h-85 m-auto mt-10 flex flex-col place-content-center place-items-center gap-8 rounded-3xl bg-gray-50 p-5 dark:bg-immich-dark-gray-card {hoverClasses}"
>
  <img {src} alt="" height="200" draggable="false" />

  {#if title}
    <h2 class="text-xl font-medium my-4">{title}</h2>
  {/if}
  <p class="text-immich-gray-text dark:text-immich-dark-gray-text font-medium text-center">{text.toUpperCase()}</p>
</svelte:element>
