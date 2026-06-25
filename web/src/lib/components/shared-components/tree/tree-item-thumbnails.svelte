<script lang="ts">
  import type { TreeNode } from '$lib/utils/tree-utils';
  import { Icon } from '@immich/ui';

  interface Props {
    items: TreeNode[];
    icon: string;
    onClick: (path: string) => void;
  }

  let { items, icon, onClick }: Props = $props();
</script>

{#if items.length > 0}
  <div class="w-full grid grid-cols-2 sm:grid-cols-4 lg:grid-cols-4 2xl:grid-cols-6">
    <!-- eslint-disable-next-line svelte/require-each-key -->
    {#each items as item}
      <button
        class="flex flex-col place-items-center gap-3 p-3 md:gap-6 md:p-6 hover:bg-immich-primary/10 dark:hover:bg-immich-primary/40 rounded-3xl"
        onclick={() => onClick(item.value)}
        title={item.value}
        type="button"
      >
        <Icon path={icon} class="text-primary" size={80} />
        <p
          class="text-sm text-black/87 dark:text-white/87 text-nowrap text-ellipsis overflow-clip w-full whitespace-pre-wrap"
        >
          {item.value}
        </p>
      </button>
    {/each}
  </div>
{/if}
