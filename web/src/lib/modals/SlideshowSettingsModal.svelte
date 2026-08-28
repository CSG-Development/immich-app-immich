<script lang="ts">
  import type { RenderedOption } from '$lib/elements/Dropdown.svelte';
  import { Field, FormModal, HelperText, NumberInput, Switch } from '@immich/ui';
  import {
    mdiArrowDownThin,
    mdiArrowUpThin,
    mdiFitToPageOutline,
    mdiFitToScreenOutline,
    mdiPanorama,
    mdiShuffle,
  } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import SettingDropdown from '../components/shared-components/settings/setting-dropdown.svelte';
  import {
    clampSlideshowDelay,
    SLIDESHOW_DELAY_MAX,
    SLIDESHOW_DELAY_MIN,
    SlideshowLook,
    SlideshowNavigation,
    SlideshowState,
    slideshowStore,
  } from '../stores/slideshow.store';

  const {
    slideshowDelay,
    showProgressBar,
    slideshowNavigation,
    slideshowLook,
    slideshowTransition,
    slideshowAutoplay,
    slideshowRepeat,
    slideshowState,
  } = slideshowStore;

  type Props = {
    onClose: () => void;
  };

  let { onClose }: Props = $props();

  // Temporary variables to hold the settings - marked as reactive with $state() but initialized with store values
  let tempSlideshowDelay = $state($slideshowDelay);
  let tempShowProgressBar = $state($showProgressBar);
  let tempSlideshowNavigation = $state($slideshowNavigation);
  let tempSlideshowLook = $state($slideshowLook);
  let tempSlideshowTransition = $state($slideshowTransition);
  let tempSlideshowAutoplay = $state($slideshowAutoplay);
  let tempSlideshowRepeat = $state($slideshowRepeat);

  const isDurationValid = $derived(
    typeof tempSlideshowDelay === 'number' &&
      Number.isFinite(tempSlideshowDelay) &&
      tempSlideshowDelay >= SLIDESHOW_DELAY_MIN &&
      tempSlideshowDelay <= SLIDESHOW_DELAY_MAX,
  );

  const navigationOptions: Record<SlideshowNavigation, RenderedOption> = {
    [SlideshowNavigation.Shuffle]: { icon: mdiShuffle, title: $t('shuffle') },
    [SlideshowNavigation.AscendingOrder]: { icon: mdiArrowUpThin, title: $t('backward') },
    [SlideshowNavigation.DescendingOrder]: { icon: mdiArrowDownThin, title: $t('forward') },
  };

  const lookOptions: Record<SlideshowLook, RenderedOption> = {
    [SlideshowLook.Contain]: { icon: mdiFitToScreenOutline, title: $t('contain') },
    [SlideshowLook.Cover]: { icon: mdiFitToPageOutline, title: $t('cover') },
    [SlideshowLook.BlurredBackground]: { icon: mdiPanorama, title: $t('blurred_background') },
  };

  const handleToggle = <Type extends SlideshowNavigation | SlideshowLook>(
    record: RenderedOption,
    options: Record<Type, RenderedOption>,
  ): undefined | Type => {
    for (const [key, option] of Object.entries(options)) {
      if (option === record) {
        return key as Type;
      }
    }
  };

  const onSubmit = () => {
    if (!isDurationValid) {
      return;
    }

    $slideshowDelay = clampSlideshowDelay(tempSlideshowDelay);
    $showProgressBar = tempShowProgressBar;
    $slideshowNavigation = tempSlideshowNavigation;
    $slideshowLook = tempSlideshowLook;
    $slideshowTransition = tempSlideshowTransition;
    $slideshowAutoplay = tempSlideshowAutoplay;
    $slideshowRepeat = tempSlideshowRepeat;
    $slideshowState = SlideshowState.PlaySlideshow;
    onClose();
  };
</script>

<FormModal size="small" title={$t('slideshow_settings')} {onClose} {onSubmit} disabled={!isDurationValid}>
  <div class="flex flex-col gap-4">
    <SettingDropdown
      title={$t('direction')}
      options={Object.values(navigationOptions)}
      selectedOption={navigationOptions[tempSlideshowNavigation]}
      onToggle={(option) => {
        tempSlideshowNavigation = handleToggle(option, navigationOptions) || tempSlideshowNavigation;
      }}
      position="bottom-right"
      class="!min-w-[180px]"
    />

    <SettingDropdown
      title={$t('look')}
      options={Object.values(lookOptions)}
      selectedOption={lookOptions[tempSlideshowLook]}
      onToggle={(option) => {
        tempSlideshowLook = handleToggle(option, lookOptions) || tempSlideshowLook;
      }}
      position="bottom-right"
      class="!min-w-[220px]"
    />

    <Field label={$t('autoplay_slideshow')}>
      <Switch bind:checked={tempSlideshowAutoplay} />
    </Field>

    <Field label={$t('show_progress_bar')}>
      <Switch bind:checked={tempShowProgressBar} />
    </Field>

    <Field label={$t('show_slideshow_transition')}>
      <Switch bind:checked={tempSlideshowTransition} />
    </Field>

    <Field label={$t('slideshow_repeat')} description={$t('slideshow_repeat_description')}>
      <Switch bind:checked={tempSlideshowRepeat} />
    </Field>

    <Field label={$t('duration')} invalid={!isDurationValid}>
      <NumberInput
        min={SLIDESHOW_DELAY_MIN}
        max={SLIDESHOW_DELAY_MAX}
        step={1}
        bind:value={tempSlideshowDelay}
        onkeydown={(event) => event.stopPropagation()}
      />
      {#if !isDurationValid}
        <HelperText color="danger">
          {$t('errors.value_must_be_between', {
            values: { min: SLIDESHOW_DELAY_MIN, max: SLIDESHOW_DELAY_MAX },
          })}
        </HelperText>
      {/if}
      <HelperText>{$t('admin.slideshow_duration_description')}</HelperText>
    </Field>
  </div>
</FormModal>
