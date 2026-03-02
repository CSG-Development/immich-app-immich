<script lang="ts">
  import type { SearchOptions } from '$lib/utils/dipatch';
  import { IconButton } from '@immich/ui';
  import { mdiClose, mdiMagnify } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import LoadingSpinner from '../components/shared-components/loading-spinner.svelte';

  interface Props {
    name: string;
    roundedBottom?: boolean;
    showLoadingSpinner: boolean;
    placeholder: string;
    onSearch?: (options: SearchOptions) => void;
    onReset?: () => void;
  }

  let {
    name = $bindable(),
    roundedBottom = true,
    showLoadingSpinner,
    placeholder,
    onSearch = () => {},
    onReset = () => {},
  }: Props = $props();

  let inputRef = $state<HTMLElement>();

  const resetSearch = () => {
    name = '';
    onReset();
    inputRef?.focus();
  };

  const handleSearch = (event: KeyboardEvent) => {
    if (event.key === 'Enter') {
      onSearch({ force: true });
    }
  };
</script>

<div
  class="px-1 flex items-center text-sm {roundedBottom
    ? 'rounded-2xl'
    : 'rounded-t-lg'} place-items-center h-full bg-immich-gray-search-bar dark:bg-immich-dark-gray-search-bar border-1 border-immich-gray-border dark:border-immich-dark-gray-border"
>
  <div class="w-14">
    <IconButton
      color="secondary"
      variant="ghost"
      icon={mdiMagnify}
      aria-label={$t('search')}
      onclick={() => onSearch({ force: true })}
      class="w-full"
    />
  </div>
  <input
    class="w-full gap-2 dark:text-white placeholder:text-immich-gray-text dark:placeholder:text-immich-dark-gray-text"
    type="text"
    {placeholder}
    bind:value={name}
    bind:this={inputRef}
    onkeydown={handleSearch}
    oninput={() => onSearch({ force: false })}
  />
  {#if showLoadingSpinner}
    <div class="flex place-items-center">
      <LoadingSpinner />
    </div>
  {/if}
  <div class="w-14">
    {#if name}
      <IconButton
        color="secondary"
        variant="ghost"
        icon={mdiClose}
        aria-label={$t('clear_value')}
        class="w-full"
        onclick={resetSearch}
      />
    {/if}
  </div>
</div>
