<script lang="ts">
  import { browser } from '$app/environment';
  import { IconButton } from '@immich/ui';
  import { mdiClose } from '@mdi/js';
  import { onDestroy, onMount, type Snippet } from 'svelte';
  import { t } from 'svelte-i18n';
  import { fly } from 'svelte/transition';

  interface Props {
    showBackButton?: boolean;
    backIcon?: string;
    tailwindClasses?: string;
    forceDark?: boolean;
    multiRow?: boolean;
    onClose?: () => void;
    leading?: Snippet;
    children?: Snippet;
    trailing?: Snippet;
    isSearch?: boolean;
  }

  let {
    showBackButton = true,
    backIcon = mdiClose,
    tailwindClasses = '',
    forceDark = false,
    multiRow = false,
    onClose = () => {},
    leading,
    children,
    trailing,
    isSearch = false,
  }: Props = $props();

  let appBarBorder = $state('bg-light border border-transparent');

  const onScroll = () => {
    if (window.scrollY > 80) {
      appBarBorder = 'border border-gray-200 bg-gray-50 dark:border-gray-600';

      if (forceDark) {
        appBarBorder = 'border border-gray-600';
      }
    } else {
      appBarBorder = 'bg-light border border-transparent';
    }
  };

  onMount(() => {
    if (browser) {
      document.addEventListener('scroll', onScroll, { passive: true });
    }
  });

  onDestroy(() => {
    if (browser) {
      document.removeEventListener('scroll', onScroll);
    }
  });
</script>

<div in:fly={{ y: 10, duration: 200 }} class="absolute top-0 w-full bg-transparent">
  <nav
    id="asset-selection-app-bar"
    class={[
      'flex h-18 md:h-21.5 relative z-50',
      appBarBorder,
      'md:mx-2 md:my-2 place-items-center md:rounded-lg p-2 max-md:p-0 transition-all',
      tailwindClasses,
      forceDark ? 'bg-black! text-white' : 'bg-white dark:bg-black',
    ]}
  >
    <div
      class="flex place-items-center sm:gap-6 justify-self-start dark:text-immich-dark-fg font-medium {isSearch
        ? ''
        : 'w-full'} {forceDark ? 'dark' : ''}"
    >
      {#if showBackButton}
        <IconButton
          aria-label={$t('close')}
          onclick={onClose}
          color="secondary"
          shape="round"
          variant="ghost"
          icon={backIcon}
          size="large"
        />
      {/if}
      <span class={isSearch ? '' : 'w-full'}>{@render leading?.()}</span>
    </div>

    <div class="w-full">
      {@render children?.()}
    </div>

    <div class="max-[350px]:me-0 max-[350px]:gap-0 me-4 flex place-items-center gap-1 justify-self-end">
      {@render trailing?.()}
    </div>
  </nav>
</div>
