import { AssetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
import { resetSavedUser, user } from '$lib/stores/user.store';
import { AssetVisibility } from '@immich/sdk';
import { timelineAssetFactory } from '@test-data/factories/asset-factory';
import { userAdminFactory } from '@test-data/factories/user-factory';
import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

vi.mock('@immich/ui', () => ({
  toastManager: {
    warning: vi.fn(),
    danger: vi.fn(),
    primary: vi.fn(),
  },
}));

vi.mock('$lib/stores/websocket', () => ({
  websocketEvents: {
    on: vi.fn(() => () => {}),
  },
}));

describe('AssetMultiSelectManager', () => {
  let sut: AssetMultiSelectManager;

  beforeEach(() => {
    sut = new AssetMultiSelectManager();
  });

  afterEach(() => {
    sut.destroy();
  });

  it('calculates derived values from selection', () => {
    sut.selectAsset(
      timelineAssetFactory.build({ isFavorite: true, visibility: AssetVisibility.Archive, isTrashed: true }),
    );
    sut.selectAsset(
      timelineAssetFactory.build({ isFavorite: true, visibility: AssetVisibility.Timeline, isTrashed: false }),
    );

    expect(sut.selectionActive).toBe(true);
    expect(sut.isAllTrashed).toBe(false);
    expect(sut.isAllArchived).toBe(false);
    expect(sut.isAllFavorite).toBe(true);
  });

  it('resets selectedAssets when clearing selection', () => {
    const assets = timelineAssetFactory.buildList(3);
    sut.selectAssets(assets);

    expect(sut.selectedAssets).toHaveLength(3);
    expect(sut.assets).toHaveLength(3);

    sut.clear();

    expect(sut.selectedAssets).toHaveLength(0);
    expect(sut.assets).toHaveLength(0);
    expect(sut.selectionActive).toBe(false);

    sut.selectAsset(timelineAssetFactory.build());

    expect(sut.selectedAssets).toHaveLength(1);
    expect(sut.assets).toHaveLength(1);
  });

  it('does not duplicate already selected assets', () => {
    const asset = timelineAssetFactory.build();
    sut.selectAsset(asset);
    sut.selectAsset(asset);

    expect(sut.selectedAssets).toHaveLength(1);
    expect(sut.assets).toHaveLength(1);
  });

  it('removes deleted assets from the current selection', () => {
    const [keep, remove] = timelineAssetFactory.buildList(2);
    sut.selectAssets([keep, remove]);

    // Simulate websocket delete event by calling the same removal path used by the manager.
    sut.removeAssetFromMultiselectGroup(remove.id);

    expect(sut.hasSelectedAsset(keep.id)).toBe(true);
    expect(sut.hasSelectedAsset(remove.id)).toBe(false);
    expect(sut.selectedAssets).toHaveLength(1);
  });
});
