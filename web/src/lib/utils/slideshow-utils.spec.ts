import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
import { SlideshowNavigation, SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
import {
  getOrderedSlideshowAssets,
  startSelectionSlideshow,
  startSlideshowFromAssets,
} from '$lib/utils/slideshow-utils';
import { isHttpError } from '@immich/sdk';
import { toastManager } from '@immich/ui';
import { assetFactory, timelineAssetFactory } from '@test-data/factories/asset-factory';
import { get } from 'svelte/store';
import { beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('@immich/ui', () => ({
  toastManager: {
    warning: vi.fn(),
    danger: vi.fn(),
    primary: vi.fn(),
  },
}));

vi.mock('@immich/sdk', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@immich/sdk')>();
  return {
    ...actual,
    isHttpError: vi.fn(),
  };
});

vi.mock('$lib/managers/asset-viewer-manager.svelte', () => ({
  assetViewerManager: {
    setAssetId: vi.fn(),
  },
}));

vi.mock('$lib/stores/websocket', () => ({
  websocketEvents: {
    on: vi.fn(() => () => {}),
  },
}));

const unavailableError = () => ({ status: 400, data: { message: 'Not found or no asset read access' } });

describe('slideshow-utils', () => {
  beforeEach(() => {
    assetMultiSelectManager.clear();
    slideshowStore.slideshowState.set(SlideshowState.None);
    vi.mocked(assetViewerManager.setAssetId).mockReset();
    vi.mocked(toastManager.warning).mockReset();
    vi.mocked(toastManager.danger).mockReset();
    vi.mocked(isHttpError).mockImplementation(
      (error: unknown): error is never =>
        typeof error === 'object' && error !== null && 'status' in error && (error as { status: number }).status === 400,
    );
  });

  describe(getOrderedSlideshowAssets.name, () => {
    const assets = timelineAssetFactory.buildList(3);

    it('returns assets in original order for descending navigation', () => {
      expect(getOrderedSlideshowAssets(assets, [], SlideshowNavigation.DescendingOrder)).toEqual([...assets]);
    });

    it('returns assets reversed for ascending order', () => {
      expect(getOrderedSlideshowAssets(assets, [], SlideshowNavigation.AscendingOrder)).toEqual([...assets].reverse());
    });

    it('returns shuffled assets when shuffle is selected', () => {
      const shuffled = [...assets].reverse();
      expect(getOrderedSlideshowAssets(assets, shuffled, SlideshowNavigation.Shuffle)).toBe(shuffled);
    });
  });

  describe(startSlideshowFromAssets.name, () => {
    it('starts slideshow with the first available asset', async () => {
      const assets = timelineAssetFactory.buildList(2);
      const response = assetFactory.build({ id: assets[0].id });
      vi.mocked(assetViewerManager.setAssetId).mockResolvedValue(response);

      await expect(startSlideshowFromAssets(assets)).resolves.toBe(true);

      expect(assetViewerManager.setAssetId).toHaveBeenCalledWith(assets[0].id);
      expect(get(slideshowStore.slideshowState)).toBe(SlideshowState.PlaySlideshow);
      expect(toastManager.warning).not.toHaveBeenCalled();
      expect(toastManager.danger).not.toHaveBeenCalled();
    });

    it('skips unavailable assets, updates selection, and continues', async () => {
      const assets = timelineAssetFactory.buildList(2);
      assetMultiSelectManager.selectAssets(assets);
      const response = assetFactory.build({ id: assets[1].id });
      vi.mocked(assetViewerManager.setAssetId)
        .mockRejectedValueOnce(unavailableError())
        .mockResolvedValueOnce(response);

      await expect(startSlideshowFromAssets(assets)).resolves.toBe(true);

      expect(assetViewerManager.setAssetId).toHaveBeenCalledTimes(2);
      expect(assetMultiSelectManager.hasSelectedAsset(assets[0].id)).toBe(false);
      expect(assetMultiSelectManager.hasSelectedAsset(assets[1].id)).toBe(true);
      expect(toastManager.warning).toHaveBeenCalled();
      expect(get(slideshowStore.slideshowState)).toBe(SlideshowState.PlaySlideshow);
    });

    it('shows an error toast when every selected asset is unavailable', async () => {
      const assets = timelineAssetFactory.buildList(2);
      assetMultiSelectManager.selectAssets(assets);
      vi.mocked(assetViewerManager.setAssetId).mockRejectedValue(unavailableError());

      await expect(startSlideshowFromAssets(assets)).resolves.toBe(false);

      expect(assetMultiSelectManager.selectedAssets).toHaveLength(0);
      expect(toastManager.danger).toHaveBeenCalled();
      expect(get(slideshowStore.slideshowState)).toBe(SlideshowState.None);
    });
  });

  describe(startSelectionSlideshow.name, () => {
    it('uses the selected assets when present', async () => {
      const assets = timelineAssetFactory.buildList(2);
      assetMultiSelectManager.selectAssets(assets);
      vi.mocked(assetViewerManager.setAssetId).mockResolvedValue(assetFactory.build({ id: assets[0].id }));

      const shuffled = await startSelectionSlideshow(SlideshowNavigation.AscendingOrder);

      expect(shuffled).toHaveLength(2);
      expect(assetViewerManager.setAssetId).toHaveBeenCalled();
    });
  });
});
