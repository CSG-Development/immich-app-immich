<script lang="ts">
  import type { Snippet } from 'svelte';

  interface Props {
    rounded?: boolean | 'full';
    children?: Snippet;
  }

  let { rounded = true, children }: Props = $props();
</script>

<span
  class="bg-primary text-subtle inline-block h-min whitespace-nowrap px-3 py-0.5 text-center align-baseline text-xs leading-none"
  class:rounded-md={rounded === true}
  class:rounded-3xl={rounded === 'full'}
>
  {@render children?.()}
</span>
