<script lang="ts">
  import type { SearchDisplayFilters } from '$lib/types';
  import { Checkbox, Label, Text } from '@immich/ui';
  import { t } from 'svelte-i18n';

  type Props = {
    filters: SearchDisplayFilters;
  };

  let { filters = $bindable() }: Props = $props();
</script>

<div id="display-options-selection">
  <fieldset>
    <Text class="mb-2" fontWeight="medium">{$t('display_options')}</Text>

    <div class="flex flex-wrap gap-x-5 gap-y-2 mt-1">
      <div class="flex items-center gap-2">
        <Checkbox id="not-in-album-checkbox" size="tiny" bind:checked={filters.isNotInAlbum} />
        <Label class="cursor-pointer" label={$t('not_in_any_album')} for="not-in-album-checkbox" />
      </div>
      <div class="flex items-center gap-2">
        <Checkbox id="archive-checkbox" size="tiny" bind:checked={filters.isArchive} />
        <Label class="cursor-pointer" label={$t('archive')} for="archive-checkbox" />
      </div>
      <div class="flex items-center gap-2">
        <Checkbox id="favorites-checkbox" size="tiny" bind:checked={filters.isFavorite} />
        <Label class="cursor-pointer" label={$t('favorites')} for="favorites-checkbox" />
      </div>
    </div>
  </fieldset>
</div>
