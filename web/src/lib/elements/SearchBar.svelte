<script lang="ts">
  import type { SearchOptions } from '$lib/utils/dipatch';
  import { IconButton, LoadingSpinner } from '@immich/ui';
  import { mdiClose, mdiMagnify } from '@mdi/js';
  import { t } from 'svelte-i18n';

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
  class="flex items-center text-sm {roundedBottom
    ? 'rounded-3xl'
    : 'rounded-t-lg'} p-2 bg-immich-primary-12 dark:bg-immich-dark-primary-12 gap-2 place-items-center h-10 md:h-full border border-immich-gray-border dark:border-immich-dark-gray-border"
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
    class="w-full gap-2 dark:text-white"
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
