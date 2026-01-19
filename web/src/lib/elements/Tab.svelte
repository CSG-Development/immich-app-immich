<script lang="ts">
  import { generateId } from '$lib/utils/generate-id';
  import type { Translations } from 'svelte-i18n';
  import { t } from 'svelte-i18n';

  interface Props {
    tabs: string[];
    labels?: string[];
    selected: string;
    label: string;
    onSelect: (selected: string) => void;
  }

  let { tabs, selected, label, labels, onSelect }: Props = $props();

  const id = `tab-${generateId()}`;

  console.log(tabs);
</script>

<fieldset
  class="dark:bg-immich-dark-gray flex h-9.5 rounded-3xl ring-gray-400 has-focus-visible:ring dark:ring-gray-600 bg-primary/20 dark:bg-primary/24"
>
  <legend class="sr-only">{label}</legend>
  {#each tabs as tab, index (`${id}-${index}`)}
    <div class="group w-full">
      <input
        type="radio"
        name={id}
        id="{id}-{index}"
        class="peer sr-only"
        value={tab}
        checked={tab === selected}
        onchange={() => onSelect(tab)}
      />
      <label
        for="{id}-{index}"
        class="flex h-full cursor-pointer justify-center items-center px-4 text-sm hover:bg-primary hover:text-immich-dark-gray group-first-of-type:rounded-s-3xl group-last-of-type:rounded-e-3xl peer-checked:bg-primary peer-checked:text-immich-dark-gray font-medium"
      >
        {labels?.[index] ?? $t(tab as Translations)}
      </label>
    </div>
  {/each}
</fieldset>
