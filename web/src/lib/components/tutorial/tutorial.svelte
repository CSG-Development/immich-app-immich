<script lang="ts">
  import { goto } from '$app/navigation';
  import { resolve } from '$app/paths';
  import onboarding1DarkUrl from '$lib/assets/onboarding-1-dark.svg';
  import onboarding1Url from '$lib/assets/onboarding-1.svg';
  import onboarding2Url from '$lib/assets/onboarding-2.svg';
  import onboarding3DarkUrl from '$lib/assets/onboarding-3-dark.svg';
  import onboarding3Url from '$lib/assets/onboarding-3.svg';
  import onboarding4DarkUrl from '$lib/assets/onboarding-4-dark.svg';
  import onboarding4Url from '$lib/assets/onboarding-4.svg';
  import onboarding5Url from '$lib/assets/onboarding-5.svg';
  import { AppRoute } from '$lib/constants';
  import { themeManager } from '$lib/managers/theme-manager.svelte';
  import { Button, IconButton, Theme } from '@immich/ui';
  import { mdiChevronLeft, mdiChevronRight } from '@mdi/js';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  const theme = $derived(themeManager.value);

  const slides = $derived([
    {
      src: theme === Theme.Light ? onboarding1Url : onboarding1DarkUrl,
      title: $t('welcome_to_immich'),
      text: $t('onboarding_step_1_text'),
    },
    {
      src: onboarding2Url,
      title: $t('onboarding_step_2_title'),
      text: $t('onboarding_step_2_text'),
    },
    {
      src: theme === Theme.Light ? onboarding3Url : onboarding3DarkUrl,
      title: $t('onboarding_step_3_title'),
      text: $t('onboarding_step_3_text'),
    },
    {
      src: theme === Theme.Light ? onboarding4Url : onboarding4DarkUrl,
      title: $t('onboarding_step_4_title'),
      text: $t('onboarding_step_4_text'),
    },
    {
      src: onboarding5Url,
      title: $t('onboarding_step_5_title'),
      text: $t('onboarding_step_5_text'),
    },
  ]);

  let currentStep = $state<number>(0);
  // eslint-disable-next-line @typescript-eslint/no-unused-vars
  let direction = $state<'next' | 'prev'>('next');

  const onNext = (): void => {
    if (currentStep < slides.length - 1) {
      direction = 'next';
      currentStep = currentStep + 1;
    }
  };

  const onPrevious = (): void => {
    if (currentStep > 0) {
      direction = 'prev';
      currentStep = currentStep - 1;
    }
  };

  const handleKeyDown = (e: KeyboardEvent): void => {
    if (e.key === 'ArrowRight') {
      onNext();
    }
    if (e.key === 'ArrowLeft') {
      onPrevious();
    }
  };

  const onDone = async () => {
    await goto(resolve(AppRoute.PHOTOS));
  };

  onMount(() => {
    globalThis.addEventListener('keydown', handleKeyDown);
    return () => globalThis.removeEventListener('keydown', handleKeyDown);
  });

  let titleLines: number[] = $state([]);
  let titleRefs: HTMLElement[] = $state([]);

  // initialize arrays once
  $effect(() => {
    for (let i = 0; i < slides.length; i++) {
      titleRefs[i] ||= null!;
      titleLines[i] ||= 0;
    }
  });

  const updateTitleLine = (i: number) => {
    const el = titleRefs[i];
    if (!el || globalThis.window === undefined) {
      return;
    }
    const lineHeight = Number.parseFloat(getComputedStyle(el).lineHeight);
    const height = el.offsetHeight;
    titleLines[i] = Math.round(height / lineHeight);
  };

  // recalc only the current slide after it renders
  $effect(() => {
    updateTitleLine(currentStep); // uses reactive currentStep and slides implicitly
  });
</script>

<div
  id="onboarding-card"
  class="flex flex-col items-center w-120 h-205.5 max-w-4xl gap-6 rounded-3xl px-10 py-10 bg-gray-50 dark:bg-[rgb(38,39,41)] text-black dark:text-immich-dark-fg overflow-hidden"
>
  <div class="relative flex items-center justify-center w-full h-[283px]">
    <IconButton
      class="absolute z-50 -left-6 w-10 h-10 text-black/87 dark:text-white/87 bg-transparent border border-[rgb(224,224,224)] dark:border-[rgb(97,97,97)] dark:bg-[rgb(66,66,66)]/47"
      shape="round"
      variant="ghost"
      color="secondary"
      aria-label={$t('previous')}
      icon={mdiChevronLeft}
      disabled={currentStep === 0}
      onclick={onPrevious}
    ></IconButton>

    <div class="relative w-full h-[283px] overflow-hidden">
      {#each slides as slide, i (i)}
        <img
          src={slide.src}
          alt={`Onboarding step ${i}`}
          class="absolute top-0 left-0 w-full object-contain transition-transform duration-500 ease-in-out opacity-0"
          class:invisible={i !== currentStep}
          style="
            transform: translateX({(i - currentStep) * 100}%);
            opacity: {i === currentStep ? 1 : 0};
          "
        />
      {/each}
    </div>

    <IconButton
      class="absolute z-50 -right-6 w-10 h-10 text-black/87 dark:text-white/87 bg-transparent border border-[rgb(224,224,224)] dark:border-[rgb(97,97,97)] dark:bg-[rgb(66,66,66)]/47"
      shape="round"
      variant="ghost"
      color="secondary"
      aria-label={$t('next')}
      icon={mdiChevronRight}
      disabled={currentStep === slides.length - 1}
      onclick={onNext}
    ></IconButton>
  </div>

  <div class="relative w-full h-full overflow-hidden">
    {#each slides as slide, i (i)}
      <p
        bind:this={titleRefs[i]}
        class="text-left font-bold text-[34px]/10 text-black/87 dark:text-white/87 w-full absolute top-0 left-0 object-contain transition-transform duration-500 ease-in-out opacity-0"
        class:invisible={i !== currentStep}
        style="
        transform: translateX({(i - currentStep) * 100}%);
        opacity: {i === currentStep ? 1 : 0};
      "
      >
        {slide.title}
      </p>
      <p
        class="text-black/87 dark:text-white/87 w-full absolute object-contain transition-transform duration-500 ease-in-out opacity-0"
        class:top-26={titleLines[i] === 2}
        class:top-16={titleLines[i] === 1}
        class:invisible={i !== currentStep}
        style="
        transform: translateX({(i - currentStep) * 100}%);
        opacity: {i === currentStep ? 1 : 0};
      "
      >
        {slide.text}
      </p>
    {/each}
  </div>

  <div class="flex w-full h-17 justify-between items-center flex-wrap mt-auto">
    <Button
      class="text-black/87 dark:text-white/87 px-0 mx-0 {currentStep === slides.length - 1 && 'invisible'}"
      variant="ghost"
      color="secondary"
      onclick={onDone}
    >
      {$t('skip')}
    </Button>

    <div class="flex justify-center items-center gap-3.75 w-30">
      {#each slides as _, i (i)}
        <button
          aria-label={String(i)}
          type="button"
          class="!w-3 !h-3 rounded-full duration-200 p-0 m-0 bg-black/87 dark:bg-white/87 {i !== currentStep &&
            'opacity-50'}"
          onclick={() => {
            direction = i > currentStep ? 'next' : 'prev';
            currentStep = i;
          }}
        ></button>
      {/each}
    </div>

    <Button
      class="text-black/87 dark:text-white/87 px-0 mx-0 {currentStep !== slides.length - 1 && 'invisible'}"
      variant="ghost"
      color="secondary"
      onclick={onDone}
    >
      {$t('done')}
    </Button>
  </div>
</div>

<style>
  img {
    transition:
      transform 0.5s ease,
      opacity 0.5s ease;
  }
  p {
    transition:
      transform 0.5s ease,
      opacity 0.5s ease;
  }
</style>
