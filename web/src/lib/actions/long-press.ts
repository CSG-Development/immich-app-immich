import type { ActionReturn } from 'svelte/action';

interface Options {
  onLongPress: () => void;
  /** Hold duration in ms before firing. Defaults to 350. */
  duration?: number;
  /** Pointer movement in px that cancels the gesture. Defaults to 10. */
  moveThreshold?: number;
}

/**
 * Invokes a callback after a sustained pointer press, suppressing the following
 * click and the native context menu. Cancels on move, scroll, or wheel.
 */
export function longPress(node: HTMLElement, options: Options): ActionReturn<Options> {
  let { onLongPress, duration = 350, moveThreshold = 10 } = options;

  let timer: ReturnType<typeof setTimeout> | null = null;
  let didPress = false;
  let startX = 0;
  let startY = 0;
  const disposeables: (() => void)[] = [];

  const preventContextMenu = (event: Event) => event.preventDefault();

  const clearTimer = () => {
    if (!timer) {
      return;
    }
    clearTimeout(timer);
    timer = null;
    for (const dispose of disposeables) {
      dispose();
    }
    disposeables.length = 0;
  };

  const start = (event: PointerEvent) => {
    // Ignore secondary buttons (e.g. right-click); those use contextmenu.
    if (event.button !== 0) {
      return;
    }

    startX = event.clientX;
    startY = event.clientY;
    didPress = false;

    timer = setTimeout(() => {
      window.getSelection()?.removeAllRanges();
      onLongPress();
      node.addEventListener('contextmenu', preventContextMenu, { once: true });
      disposeables.push(() => node.removeEventListener('contextmenu', preventContextMenu));
      didPress = true;
    }, duration);
  };

  const onClick = (event: MouseEvent) => {
    if (!didPress) {
      return;
    }
    event.stopPropagation();
    event.preventDefault();
  };

  const onMove = (event: PointerEvent) => {
    if (Math.abs(startX - event.clientX) >= moveThreshold || Math.abs(startY - event.clientY) >= moveThreshold) {
      clearTimer();
    }
  };

  node.addEventListener('click', onClick);
  node.addEventListener('pointerdown', start, true);
  node.addEventListener('pointerup', clearTimer, { capture: true, passive: true });
  node.addEventListener('pointercancel', clearTimer, { capture: true, passive: true });

  document.addEventListener('scroll', clearTimer, { capture: true, passive: true });
  document.addEventListener('wheel', clearTimer, { capture: true, passive: true });
  document.addEventListener('pointermove', onMove, { capture: true, passive: true });

  return {
    update(next: Options) {
      onLongPress = next.onLongPress;
      duration = next.duration ?? 350;
      moveThreshold = next.moveThreshold ?? 10;
    },
    destroy() {
      clearTimer();
      node.removeEventListener('click', onClick);
      node.removeEventListener('pointerdown', start, true);
      node.removeEventListener('pointerup', clearTimer, true);
      node.removeEventListener('pointercancel', clearTimer, true);
      document.removeEventListener('scroll', clearTimer, true);
      document.removeEventListener('wheel', clearTimer, true);
      document.removeEventListener('pointermove', onMove, true);
    },
  };
}
