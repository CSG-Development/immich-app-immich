<script lang="ts">
  import type { HeaderButtonActionItem } from '$lib/types';
  import { Button, IconButton } from '@immich/ui';

  type Props = {
    action: HeaderButtonActionItem;
    /** Show icon-only below this breakpoint; full labeled button at and above it. */
    iconOnlyBelow?: 'sm' | 'md';
  };

  const { action, iconOnlyBelow }: Props = $props();
  const { title, icon, color = 'secondary', onAction } = $derived(action);
</script>

{#if action.$if?.() ?? true}
  {#if iconOnlyBelow === 'sm' && icon}
    <IconButton
      class="sm:hidden"
      variant="ghost"
      shape="round"
      size="small"
      {color}
      {icon}
      aria-label={title}
      onclick={() => onAction(action)}
    />
    <Button
      class="hidden sm:flex"
      variant="ghost"
      size="small"
      {color}
      leadingIcon={icon}
      onclick={() => onAction(action)}
      title={action.data?.title}
    >
      {title}
    </Button>
  {:else if iconOnlyBelow === 'md' && icon}
    <IconButton
      class="md:hidden"
      variant="ghost"
      shape="round"
      size="small"
      {color}
      {icon}
      aria-label={title}
      onclick={() => onAction(action)}
    />
    <Button
      class="hidden md:flex"
      variant="ghost"
      size="small"
      {color}
      leadingIcon={icon}
      onclick={() => onAction(action)}
      title={action.data?.title}
    >
      {title}
    </Button>
  {:else}
    <Button
      variant="ghost"
      size="small"
      {color}
      leadingIcon={icon}
      onclick={() => onAction(action)}
      title={action.data?.title}
    >
      {title}
    </Button>
  {/if}
{/if}
