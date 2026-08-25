import { persisted } from 'svelte-persisted-store';
import { writable, type Writable } from 'svelte/store';

export enum SlideshowState {
  PlaySlideshow = 'play-slideshow',
  StopSlideshow = 'stop-slideshow',
  None = 'none',
}

export enum SlideshowNavigation {
  Shuffle = 'shuffle',
  AscendingOrder = 'ascending-order',
  DescendingOrder = 'descending-order',
}

export enum SlideshowLook {
  Contain = 'contain',
  Cover = 'cover',
  BlurredBackground = 'blurred-background',
}

/** Minimum slideshow image duration in seconds. */
export const SLIDESHOW_DELAY_MIN = 1;
/** Maximum slideshow image duration in seconds (1 hour). */
export const SLIDESHOW_DELAY_MAX = 3600;

export const clampSlideshowDelay = (value: number): number =>
  Math.min(SLIDESHOW_DELAY_MAX, Math.max(SLIDESHOW_DELAY_MIN, value));

const sanitizeSlideshowDelay = (value: number): number =>
  typeof value === 'number' && Number.isFinite(value) ? clampSlideshowDelay(value) : SLIDESHOW_DELAY_MIN;

const createClampedSlideshowDelayStore = (initial: number): Writable<number> => {
  const store = persisted<number>('slideshow-delay', initial, {});

  return {
    subscribe: (run, invalidate) =>
      store.subscribe((value) => {
        run(sanitizeSlideshowDelay(value));
      }, invalidate),
    set: (value) => store.set(sanitizeSlideshowDelay(value)),
    update: (updater) =>
      store.update((value) => sanitizeSlideshowDelay(updater(sanitizeSlideshowDelay(value)))),
  };
};

export const slideshowLookCssMapping: Record<SlideshowLook, string> = {
  [SlideshowLook.Contain]: 'object-contain',
  [SlideshowLook.Cover]: 'object-cover',
  [SlideshowLook.BlurredBackground]: 'object-contain',
};

function createSlideshowStore() {
  const restartState = writable<boolean>(false);
  const stopState = writable<boolean>(false);

  const slideshowNavigation = persisted<SlideshowNavigation>(
    'slideshow-navigation',
    SlideshowNavigation.DescendingOrder,
  );
  const slideshowLook = persisted<SlideshowLook>('slideshow-look', SlideshowLook.Contain);
  const slideshowState = writable<SlideshowState>(SlideshowState.None);
  const isShuffled = writable<boolean>(false);

  const showProgressBar = persisted<boolean>('slideshow-show-progressbar', true);
  const slideshowDelay = createClampedSlideshowDelayStore(5);
  const slideshowTransition = persisted<boolean>('slideshow-transition', true);
  const slideshowAutoplay = persisted<boolean>('slideshow-autoplay', true, {});
  const slideshowRepeat = persisted<boolean>('slideshow-repeat', false);

  return {
    restartProgress: {
      subscribe: restartState.subscribe,
      set: (value: boolean) => {
        // Trigger an action whenever the restartProgress is set to true. Automatically
        // reset the restart state after that
        if (value) {
          restartState.set(true);
          restartState.set(false);
        }
      },
    },
    stopProgress: {
      subscribe: stopState.subscribe,
      set: (value: boolean) => {
        // Trigger an action whenever the stopProgress is set to true. Automatically
        // reset the stop state after that
        if (value) {
          stopState.set(true);
          stopState.set(false);
        }
      },
    },
    slideshowNavigation,
    slideshowLook,
    slideshowState,
    slideshowDelay,
    showProgressBar,
    slideshowTransition,
    slideshowAutoplay,
    slideshowRepeat,
    isShuffled,
  };
}

export const slideshowStore = createSlideshowStore();
