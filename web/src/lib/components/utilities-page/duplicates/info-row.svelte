<script lang="ts">
  import { Icon, Text } from '@immich/ui';
  import type { Snippet } from 'svelte';

  interface Props {
    icon: string;
    children?: Snippet;
    borderBottom?: boolean;
    highlight?: boolean;
    active?: boolean;
    title?: string;
  }

  let { icon, children, borderBottom = true, highlight = false, active = false, title }: Props = $props();

  const iconClass = $derived(
    active ? 'text-white dark:text-white' : highlight ? 'text-primary-700/75' : 'text-dark/25',
  );

  const textClass = $derived(
    highlight
      ? active
        ? 'text-white dark:text-white'
        : 'text-primary-700'
      : active
        ? 'text-white/90 dark:text-white/90'
        : '',
  );
</script>

<div class="grid grid-cols-[25px_1fr] w-full px-1 py-0.5" class:border-b={borderBottom} {title}>
  <Icon {icon} size="18" class={iconClass} />
  <div class="justify-self-end text-end rounded px-1 transition-colors w-full overflow-hidden">
    <Text
      size="tiny"
      fontWeight={highlight ? 'semi-bold' : 'normal'}
      class={`${textClass} text-ellipsis w-full overflow-hidden`}
    >
      {@render children?.()}
    </Text>
  </div>
</div>
