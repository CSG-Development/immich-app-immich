<script lang="ts">
  import { themeManager } from '$lib/managers/theme-manager.svelte';
  import { Logo } from '@immich/ui';
  import { t } from 'svelte-i18n';

  interface Props {
    centered?: boolean;
    logoSize?: 'sm' | 'lg';
  }

  let { centered = false, logoSize = 'sm' }: Props = $props();
</script>

<div
  class="flex gap-1 mt-2 place-items-center dark:bg-immich-dark-primary/10 bg-gray-200/50 p-2 rounded-lg bg-clip-padding border border-transparent relative supporter-effect"
  class:place-content-center={centered}
>
  <Logo class={logoSize === 'sm' ? 'h-6' : 'h-8'} variant="icon" appTheme={themeManager.value} />
  <p class="dark:text-gray-100">{$t('purchase_account_info')}</p>
</div>

<style lang="postcss">
  @reference "tailwindcss";

  .supporter-effect::after {
    @apply absolute inset-0 rounded-lg opacity-0 transition-opacity content-[''];
  }

  .supporter-effect:hover::after {
    @apply opacity-100;
    background: linear-gradient(
      to right,
      rgba(16, 132, 254, 0.25),
      rgba(229, 125, 175, 0.25),
      rgba(254, 36, 29, 0.25),
      rgba(255, 183, 0, 0.25),
      rgba(22, 193, 68, 0.25)
    );
    animation: gradient 10s ease infinite;
    background-size: 400% 400%;
  }

  @keyframes gradient {
    0% {
      background-position: 0% 50%;
    }
    50% {
      background-position: 100% 50%;
    }
    100% {
      background-position: 0% 50%;
    }
  }
</style>
