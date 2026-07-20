import { render, waitFor } from '@testing-library/svelte';
import { tick } from 'svelte';
import ProgressBar from './progress-bar.svelte';

const getProgressWidthPercent = (baseElement: HTMLElement): number => {
  const bar = baseElement.querySelector('span');
  expect(bar).not.toBeNull();
  return Number.parseFloat(bar!.style.width);
};

describe('ProgressBar component', () => {
  it('does not reset progress when onDone callback identity changes', async () => {
    const onDone1 = vi.fn();
    const { baseElement, rerender } = render(ProgressBar, {
      props: {
        autoplay: true,
        duration: 0.25,
        onDone: onDone1,
      },
    });

    await waitFor(() => expect(getProgressWidthPercent(baseElement)).toBeGreaterThan(15));
    const widthBeforeRerender = getProgressWidthPercent(baseElement);

    const onDone2 = vi.fn();
    await rerender({
      autoplay: true,
      duration: 0.25,
      onDone: onDone2,
    });
    await tick();

    // A duration-effect re-run would recreate the tween at 0%. Callback identity must not do that.
    expect(getProgressWidthPercent(baseElement)).toBeGreaterThanOrEqual(widthBeforeRerender - 1);

    await waitFor(() => expect(onDone2).toHaveBeenCalledOnce(), { timeout: 2000 });
    expect(onDone1).not.toHaveBeenCalled();
    expect(onDone2).toHaveBeenCalledTimes(1);
  });

  it('calls onDone once when progress completes', async () => {
    const onDone = vi.fn();
    render(ProgressBar, {
      props: {
        autoplay: true,
        duration: 0.05,
        onDone,
      },
    });

    await waitFor(() => expect(onDone).toHaveBeenCalledOnce(), { timeout: 2000 });
    expect(onDone).toHaveBeenCalledTimes(1);
  });
});
