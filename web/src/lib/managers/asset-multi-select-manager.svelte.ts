import { eventManager } from '$lib/managers/event-manager.svelte';
import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
import { user } from '$lib/stores/user.store';
import { websocketEvents } from '$lib/stores/websocket';
import { AssetVisibility, type UserAdminResponseDto } from '@immich/sdk';
import { SvelteMap, SvelteSet } from 'svelte/reactivity';
import { fromStore } from 'svelte/store';

export type AssetMultiSelectOptions = {
  resetOnNavigate?: boolean;
};
export class AssetMultiSelectManager {
  #selectedMap = new SvelteMap<string, TimelineAsset>();
  #user = fromStore<UserAdminResponseDto | undefined>(user);
  #userId = $derived(this.#user.current?.id);

  selectAll = $state(false);
  startAsset = $state<TimelineAsset | null>(null);

  selectedGroup = new SvelteSet<string>();
  selectedAssets = $state<TimelineAsset[]>([]);

  candidates = $state<TimelineAsset[]>([]);

  selectionActive = $derived(this.#selectedMap.size > 0);

  assets = $derived(Array.from(this.#selectedMap.values()));
  ownedAssets = $derived(this.#userId ? this.assets.filter((asset) => asset.ownerId === this.#userId) : this.assets);

  isAllTrashed = $derived(this.assets.every((asset) => asset.isTrashed));
  isAllArchived = $derived(this.assets.every((asset) => asset.visibility === AssetVisibility.Archive));
  isAllFavorite = $derived(this.assets.every((asset) => asset.isFavorite));
  isAllUserOwned = $derived(this.assets.every((asset) => asset.ownerId === this.#userId));

  #unsubscribers: Array<() => void> = [];

  constructor(options?: AssetMultiSelectOptions) {
    const { resetOnNavigate = false } = options ?? {};
    if (resetOnNavigate) {
      this.#unsubscribers.push(eventManager.on({ AppNavigate: () => this.clear() }));
    }

    // Keep selection in sync when assets are removed in another tab/session.
    this.#unsubscribers.push(
      websocketEvents.on('on_asset_delete', (id) => this.removeAssetFromMultiselectGroup(id)),
      websocketEvents.on('on_asset_trash', (ids) => {
        for (const id of ids) {
          this.removeAssetFromMultiselectGroup(id);
        }
      }),
      websocketEvents.on('on_asset_hidden', (id) => this.removeAssetFromMultiselectGroup(id)),
    );
  }

  destroy() {
    for (const unsubscribe of this.#unsubscribers) {
      unsubscribe();
    }
    this.#unsubscribers = [];
  }

  getOwnedAssets() {
    return this.#userId ? this.assets.filter((asset) => asset.ownerId === this.#userId) : this.assets;
  }

  hasSelectedAsset(assetId: string) {
    return this.#selectedMap.has(assetId);
  }

  hasSelectionCandidate(assetId: string) {
    return this.candidates.some((asset) => asset.id === assetId);
  }

  selectAsset(asset: TimelineAsset) {
    if (this.#selectedMap.has(asset.id)) {
      return;
    }

    this.#selectedMap.set(asset.id, asset);
    this.selectedAssets.push(asset);
  }

  selectAssets(assets: TimelineAsset[]) {
    for (const asset of assets) {
      this.selectAsset(asset);
    }
  }

  removeAssetFromMultiselectGroup(assetId: string) {
    this.#selectedMap.delete(assetId);
    this.selectedAssets = this.selectedAssets.filter((asset) => asset.id !== assetId);
  }

  addGroupToMultiselectGroup(group: string) {
    this.selectedGroup.add(group);
  }

  removeGroupFromMultiselectGroup(group: string) {
    this.selectedGroup.delete(group);
  }

  setAssetSelectionStart(asset: TimelineAsset | null) {
    this.startAsset = asset;
  }

  setAssetSelectionCandidates(assets: TimelineAsset[]) {
    this.candidates = assets;
  }

  clearCandidates() {
    this.candidates = [];
  }

  clear() {
    this.selectAll = false;

    // Multi-selection
    this.#selectedMap.clear();
    this.selectedAssets = [];
    this.selectedGroup.clear();

    // Range selection
    this.candidates = [];
    this.startAsset = null;
  }
}

export const assetMultiSelectManager = new AssetMultiSelectManager({ resetOnNavigate: true });
