import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
import { SlideshowNavigation, SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
import { handleError } from '$lib/utils/handle-error';
import type { TimelineDateTime } from '$lib/utils/timeline-util';
import { isHttpError } from '@immich/sdk';
import { toastManager } from '@immich/ui';
import { t } from 'svelte-i18n';
import { get } from 'svelte/store';

const toTimestamp = (date: TimelineDateTime) =>
  new Date(date.year, date.month - 1, date.day, date.hour, date.minute, date.second, date.millisecond).getTime();

export const isAssetUnavailableError = (error: unknown) =>
  isHttpError(error) && (error.status === 400 || error.status === 404);

export const getOrderedSlideshowAssets = (
  assets: TimelineAsset[],
  shuffledAssets: TimelineAsset[],
  nav: SlideshowNavigation,
): TimelineAsset[] => {
  if (nav === SlideshowNavigation.Shuffle) {
    return shuffledAssets;
  }

  if (nav === SlideshowNavigation.AscendingOrder) {
    return [...assets].reverse();
  }

  return [...assets];
};

/**
 * Opens the asset viewer on the first available asset and starts the slideshow.
 * Unavailable assets (deleted elsewhere, no access, etc.) are removed from the
 * current selection; a toast is shown when any were skipped or none remain.
 */
export const startSlideshowFromAssets = async (assetsInOrder: TimelineAsset[]): Promise<boolean> => {
  const $t = get(t);
  const unavailableIds: string[] = [];

  for (const asset of assetsInOrder) {
    try {
      await assetViewerManager.setAssetId(asset.id);
      slideshowStore.slideshowState.set(SlideshowState.PlaySlideshow);

      if (unavailableIds.length > 0) {
        toastManager.warning(
          $t('some_selected_assets_unavailable', { values: { count: unavailableIds.length } }),
        );
      }

      return true;
    } catch (error) {
      if (!isAssetUnavailableError(error)) {
        handleError(error, $t('errors.unable_to_play_slideshow'));
        return false;
      }

      unavailableIds.push(asset.id);
      assetMultiSelectManager.removeAssetFromMultiselectGroup(asset.id);
    }
  }

  if (unavailableIds.length > 0 || assetsInOrder.length === 0) {
    toastManager.danger($t('errors.unable_to_play_slideshow'));
  }

  return false;
};

/**
 * Prepares the current multi-select (or optional fallback asset), starts the slideshow,
 * and returns the shuffled selection with unavailable assets filtered out.
 */
export const startSelectionSlideshow = async (
  nav: SlideshowNavigation,
  options?: { fallbackAsset?: TimelineAsset | null },
): Promise<TimelineAsset[]> => {
  const selected = assetMultiSelectManager.selectedAssets;

  if (selected.length === 0) {
    if (options?.fallbackAsset) {
      await startSlideshowFromAssets([options.fallbackAsset]);
    }
    return [];
  }

  selected.sort((a, b) => toTimestamp(b.fileCreatedAt) - toTimestamp(a.fileCreatedAt));
  const shuffled = [...selected].sort(() => Math.random() - 0.5);
  const ordered = getOrderedSlideshowAssets(selected, shuffled, nav);
  await startSlideshowFromAssets(ordered);

  return shuffled.filter((asset) => assetMultiSelectManager.hasSelectedAsset(asset.id));
};
