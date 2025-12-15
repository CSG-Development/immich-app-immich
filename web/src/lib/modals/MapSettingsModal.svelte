<script lang="ts">
  import Combobox, { type ComboBoxOption } from '$lib/components/shared-components/combobox.svelte';
  import DateInput from '$lib/elements/DateInput.svelte';
  import type { MapSettings } from '$lib/stores/preferences.store';
  import { Button, Field, HStack, Modal, ModalBody, ModalFooter, Stack, Switch } from '@immich/ui';
  import { Duration } from 'luxon';
  import { t } from 'svelte-i18n';
  import { fly } from 'svelte/transition';

  interface Props {
    settings: MapSettings;
    onClose: (settings?: MapSettings) => void;
  }

  let { settings: initialValues, onClose }: Props = $props();
  let settings = $state(initialValues);

  let customDateRange = $state(!!settings.dateAfter || !!settings.dateBefore);

  const onsubmit = (event: Event) => {
    event.preventDefault();
    onClose(settings);
  };

  let selectedOption: ComboBoxOption | undefined = $state(undefined);

  const options = [
    {
      value: '',
      label: $t('all'),
    },
    {
      value: Duration.fromObject({ hours: 24 }).toISO() || '',
      label: $t('past_durations.hours', { values: { hours: 24 } }),
    },
    {
      value: Duration.fromObject({ days: 7 }).toISO() || '',
      label: $t('past_durations.days', { values: { days: 7 } }),
    },
    {
      value: Duration.fromObject({ days: 30 }).toISO() || '',
      label: $t('past_durations.days', { values: { days: 30 } }),
    },
    {
      value: Duration.fromObject({ years: 1 }).toISO() || '',
      label: $t('past_durations.years', { values: { years: 1 } }),
    },
    {
      value: Duration.fromObject({ years: 3 }).toISO() || '',
      label: $t('past_durations.years', { values: { years: 3 } }),
    },
  ];

  const handleSelect = (option?: ComboBoxOption) => {
    if (!option) {
      return;
    }

    settings.relativeDate = option.value;
  };
</script>

<Modal title={$t('map_settings')} {onClose} size="small">
  <ModalBody>
    <form {onsubmit} id="map-settings-form">
      <Stack gap={4}>
        <Field label={$t('allow_dark_mode')}>
          <Switch bind:checked={settings.allowDarkMode} />
        </Field>
        <Field label={$t('only_favorites')}>
          <Switch bind:checked={settings.onlyFavorites} />
        </Field>
        <Field label={$t('include_archived')}>
          <Switch bind:checked={settings.includeArchived} />
        </Field>
        <Field label={$t('include_shared_partner_assets')}>
          <Switch bind:checked={settings.withPartners} />
        </Field>
        <Field label={$t('include_shared_albums')}>
          <Switch bind:checked={settings.withSharedAlbums} />
        </Field>

        {#if customDateRange}
          <div in:fly={{ y: 10, duration: 200 }} class="flex flex-col gap-4">
            <div class="flex items-center justify-between gap-8">
              <label class="immich-form-label shrink-0 text-sm" for="date-after">{$t('date_after')}</label>
              <DateInput
                class="immich-form-input w-40"
                type="date"
                id="date-after"
                max={settings.dateBefore}
                bind:value={settings.dateAfter}
              />
            </div>
            <div class="flex items-center justify-between gap-8">
              <label class="immich-form-label shrink-0 text-sm" for="date-before">{$t('date_before')}</label>
              <DateInput class="immich-form-input w-40" type="date" id="date-before" bind:value={settings.dateBefore} />
            </div>
            <div class="flex justify-center text-xs">
              <Button
                color="primary"
                size="small"
                variant="ghost"
                onclick={() => {
                  customDateRange = false;
                  settings.dateAfter = '';
                  settings.dateBefore = '';
                }}
              >
                {$t('remove_custom_date_range')}
              </Button>
            </div>
          </div>
        {:else}
          <div in:fly={{ y: -10, duration: 200 }} class="flex flex-col gap-1">
            <Combobox label={$t('date_range')} {options} bind:selectedOption onSelect={handleSelect} />
            <div class="text-xs pt-4">
              <Button
                color="primary"
                size="small"
                variant="ghost"
                onclick={() => {
                  customDateRange = true;
                  settings.relativeDate = '';
                }}
              >
                {$t('use_custom_date_range')}
              </Button>
            </div>
          </div>
        {/if}
      </Stack>
    </form>
  </ModalBody>

  <ModalFooter>
    <HStack fullWidth>
      <Button color="secondary" shape="round" fullWidth onclick={() => onClose()}>{$t('cancel')}</Button>
      <Button type="submit" shape="round" fullWidth form="map-settings-form">{$t('save')}</Button>
    </HStack>
  </ModalFooter>
</Modal>
