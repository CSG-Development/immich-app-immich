<script lang="ts">
  import { generateId } from '$lib/utils/generate-id';

  interface MetadataListItem {
    title: string;
    value?: string | number | null;
  }

  interface Props {
    items: MetadataListItem[];
  }

  let { items = [] }: Props = $props();
</script>

{#each items as item, index (index)}
  {@const id: string = generateId()}
  {@const sliderId = `${id}-slider`}
  {@const valueId = item.value ? `${id}-value` : undefined}

  <div class="flex place-items-center justify-between py-2">
    <div class="me-2">
      <div class="flex h-[26px] place-items-center gap-1">
        <label class="font-medium text-primary text-xs" for={sliderId}>
          {item.title}
        </label>
      </div>

      <p id={valueId} class="dark:text-immich-dark-fg">{item.value ?? '-'}</p>
    </div>
  </div>
{/each}
