<script lang="ts">
  import { ProgressBarStatus } from '$lib/constants';

  import { onMount, untrack } from 'svelte';
  import { tweened } from 'svelte/motion';

  interface Props {
    /**
     * Autoplay on mount
     * @default false
     */
    autoplay?: boolean;
    /**
     * Progress bar status
     */
    status?: ProgressBarStatus;
    hidden?: boolean;
    duration?: number;
    onDone: () => void;
    onPlaying?: () => void;
    onPaused?: () => void;
  }

  let {
    autoplay = false,
    status = $bindable(),
    hidden = false,
    duration = 5,
    onDone,
    onPlaying = () => {},
    onPaused = () => {},
  }: Props = $props();

  const onChange = async (progressDuration: number) => {
    doneFired = false;
    progress = setDuration(progressDuration);
    await play();
  };

  let progress = setDuration(duration);
  let doneFired = false;

  // Only react to duration changes — do not track callback/status reads inside play().
  $effect(() => {
    const progressDuration = duration;
    untrack(() => {
      void onChange(progressDuration).catch((error) => {
        console.error('[progress-bar]:onChange', error);
      });
    });
  });

  $effect(() => {
    if ($progress !== 1) {
      doneFired = false;
      return;
    }

    if (doneFired) {
      return;
    }

    doneFired = true;
    untrack(() => {
      onDone();
    });
  });

  onMount(async () => {
    if (autoplay) {
      status = ProgressBarStatus.Playing;
      await play();
    } else {
      status = ProgressBarStatus.Paused;
      await progress.set(0);
    }
  });

  export const play = async () => {
    status = ProgressBarStatus.Playing;
    onPlaying();
    await progress.set(1);
  };

  export const pause = async () => {
    status = ProgressBarStatus.Paused;
    onPaused();
    await progress.set($progress);
  };

  export const restart = async () => {
    doneFired = false;
    await progress.set(0);

    if (status !== ProgressBarStatus.Paused) {
      await play();
    }
  };

  export const resetProgress = async () => {
    doneFired = false;
    await progress.set(0);
  };

  function setDuration(newDuration: number) {
    return tweened<number>(0, {
      duration: (from: number, to: number) => (to ? newDuration * 1000 * (to - from) : 0),
    });
  }
</script>

{#if !hidden}
  <span class="absolute start-0 h-[3px] bg-immich-primary shadow-2xl" style:width={`${$progress * 100}%`}></span>
{/if}
