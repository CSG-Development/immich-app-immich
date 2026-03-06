<script lang="ts">
  import type { PersonResponseDto } from '@immich/sdk';

  interface Props {
    people: PersonResponseDto[];
    hasNextPage?: boolean | undefined;
    loadNextPage: () => void;
    children?: import('svelte').Snippet<[{ person: PersonResponseDto; index: number }]>;
    isVisibilityPage?: boolean;
  }

  let { people, hasNextPage = undefined, loadNextPage, children, isVisibilityPage = false }: Props = $props();

  let lastPersonContainer: HTMLElement | undefined = $state();

  const intersectionObserver = new IntersectionObserver((entries) => {
    const entry = entries.find((entry) => entry.target === lastPersonContainer);
    if (entry?.isIntersecting) {
      loadNextPage();
    }
  });

  $effect(() => {
    if (lastPersonContainer) {
      intersectionObserver.disconnect();
      intersectionObserver.observe(lastPersonContainer);
    }
  });
</script>

<div
  class="pt-2 md:pt-8.5 w-full grid grid-cols-2 sm:grid-cols-3 gap-2 {isVisibilityPage
    ? 'md:gap-3 md:grid-cols-[repeat(auto-fit,minmax(15rem,max-content))]'
    : 'md:gap-4 md:grid-cols-[repeat(auto-fit,minmax(9.75rem,max-content))]'}"
>
  {#each people as person, index (person.id)}
    {#if hasNextPage && index === people.length - 1}
      <div bind:this={lastPersonContainer}>
        {@render children?.({ person, index })}
      </div>
    {:else}
      {@render children?.({ person, index })}
    {/if}
  {/each}
</div>
