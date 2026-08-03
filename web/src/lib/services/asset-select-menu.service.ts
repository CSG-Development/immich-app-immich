import { assetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
import { authManager } from '$lib/managers/auth-manager.svelte';
import { featureFlagsManager } from '$lib/managers/feature-flags-manager.svelte';
import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
import AssetDeleteConfirmModal from '$lib/modals/AssetDeleteConfirmModal.svelte';
import AssetSelectionChangeDateModal from '$lib/modals/AssetSelectionChangeDateModal.svelte';
import AssetTagModal from '$lib/modals/AssetTagModal.svelte';
import AssetUpdateDescriptionConfirmModal from '$lib/modals/AssetUpdateDescriptionConfirmModal.svelte';
import GeolocationPointPickerModal from '$lib/modals/GeolocationPointPickerModal.svelte';
import { showDeleteModal } from '$lib/stores/preferences.store';
import { preferences, user } from '$lib/stores/user.store';
import {
  type OnArchive,
  type OnDelete,
  type OnLink,
  type OnSetVisibility,
  type OnStack,
  type OnUndoDelete,
  type OnUnlink,
  type OnUnstack,
  deleteAssets,
} from '$lib/utils/actions';
import { archiveAssets, deleteStack, downloadArchive, getOwnedAssetsWithWarning, stackAssets } from '$lib/utils/asset-utils';
import { handleError } from '$lib/utils/handle-error';
import { fromTimelinePlainDateTime, toTimelineAsset } from '$lib/utils/timeline-util';
import { AssetVisibility, getAssetInfo, updateAsset, updateAssets } from '@immich/sdk';
import { MenuItemType, modalManager, toastManager, type ActionItem, type MenuItems } from '@immich/ui';
import {
  mdiArchiveArrowDownOutline,
  mdiArchiveArrowUpOutline,
  mdiCalendarEditOutline,
  mdiCogRefreshOutline,
  mdiDatabaseRefreshOutline,
  mdiDownload,
  mdiImageMultipleOutline,
  mdiImageOffOutline,
  mdiImageRefreshOutline,
  mdiLinkOff,
  mdiLockOpenVariantOutline,
  mdiLockOutline,
  mdiMapMarkerMultipleOutline,
  mdiMotionPlayOutline,
  mdiPresentationPlay,
  mdiTagMultipleOutline,
  mdiText,
  mdiTrashCanOutline,
} from '@mdi/js';
import { DateTime } from 'luxon';
import type { MessageFormatter } from 'svelte-i18n';
import { get } from 'svelte/store';
import { getAssetBulkActions, handleDownloadAsset } from './asset.service';

export type AssetSelectMenuOptions = {
  onAssetDelete: OnDelete;
  onUndoDelete?: OnUndoDelete;
  onArchive?: OnArchive;
  onVisibilitySet?: OnSetVisibility;
  onStartSlideshow?: () => void;
  onStack?: OnStack;
  onUnstack?: OnUnstack;
  onLink?: OnLink;
  onUnlink?: OnUnlink;
  filename?: string;
  unarchive?: boolean;
  forceDelete?: boolean;
  unlock?: boolean;
  showSlideshow?: boolean;
  showDownload?: boolean;
  showStack?: boolean;
  showLinkLivePhoto?: boolean;
  showChangeDate?: boolean;
  showChangeDescription?: boolean;
  showChangeLocation?: boolean;
  showArchive?: boolean;
  showTag?: boolean;
  showDelete?: boolean;
  showVisibility?: boolean;
  showJobs?: boolean;
  showAddToAlbum?: boolean;
  extraItems?: MenuItems;
};

export const getAssetSelectMenuItems = ($t: MessageFormatter, options: AssetSelectMenuOptions): MenuItems => {
  const {
    onAssetDelete,
    onUndoDelete,
    onArchive,
    onVisibilitySet,
    onStartSlideshow,
    onStack,
    onUnstack,
    onLink,
    onUnlink,
    filename = 'immich.zip',
    unarchive = false,
    forceDelete = false,
    unlock = false,
    showSlideshow = false,
    showDownload = true,
    showStack = false,
    showLinkLivePhoto = false,
    showChangeDate = true,
    showChangeDescription = true,
    showChangeLocation = true,
    showArchive = true,
    showTag = true,
    showDelete = true,
    showVisibility = true,
    showJobs = false,
    showAddToAlbum = false,
    extraItems = [],
  } = options;

  const Jobs = getAssetBulkActions($t);

  const Slideshow: ActionItem = {
    title: $t('slideshow'),
    icon: mdiPresentationPlay,
    $if: () => showSlideshow && assetMultiSelectManager.selectedAssets.length > 1,
    onAction: () => onStartSlideshow?.(),
  };

  const Download: ActionItem = {
    title: $t('download'),
    icon: mdiDownload,
    $if: () => showDownload,
    onAction: async () => {
      const assets = assetMultiSelectManager.assets;
      if (assets.length === 1) {
        assetMultiSelectManager.clear();
        const asset = await getAssetInfo({ ...authManager.params, id: assets[0].id });
        await handleDownloadAsset(asset, { edited: true });
        return;
      }
      assetMultiSelectManager.clear();
      await downloadArchive(filename, { assetIds: assets.map((asset) => asset.id) });
    },
  };

  const Stack: ActionItem = {
    title: $t('stack'),
    icon: mdiImageMultipleOutline,
    $if: () => showStack && !isSingleStackedAssetSelected(),
    onAction: async () => {
      const result = await stackAssets(assetMultiSelectManager.ownedAssets);
      onStack?.(result);
      assetMultiSelectManager.clear();
    },
  };

  const Unstack: ActionItem = {
    title: $t('unstack'),
    icon: mdiImageOffOutline,
    $if: () => showStack && isSingleStackedAssetSelected(),
    onAction: async () => {
      const selectedAssets = assetMultiSelectManager.ownedAssets;
      if (selectedAssets.length !== 1 || !selectedAssets[0].stack) {
        return;
      }
      const unstackedAssets = await deleteStack([selectedAssets[0].stack.id]);
      if (unstackedAssets) {
        onUnstack?.(unstackedAssets.map((asset) => toTimelineAsset(asset)));
      }
      assetMultiSelectManager.clear();
    },
  };

  const LinkLivePhoto: ActionItem = {
    title: $t('link_motion_video'),
    icon: mdiMotionPlayOutline,
    $if: () => showLinkLivePhoto && assetMultiSelectManager.assets.length !== 1,
    onAction: async () => {
      let [still, motion] = assetMultiSelectManager.ownedAssets;
      if ((still as TimelineAsset).isVideo) {
        [still, motion] = [motion, still];
      }
      try {
        const stillResponse = await updateAsset({ id: still.id, updateAssetDto: { livePhotoVideoId: motion.id } });
        onLink?.({ still: toTimelineAsset(stillResponse), motion: motion as TimelineAsset });
        assetMultiSelectManager.clear();
      } catch (error) {
        handleError(error, $t('errors.unable_to_link_motion_video'));
      }
    },
  };

  const UnlinkLivePhoto: ActionItem = {
    title: $t('unlink_motion_video'),
    icon: mdiLinkOff,
    $if: () => showLinkLivePhoto && assetMultiSelectManager.assets.length === 1,
    onAction: async () => {
      const [still] = assetMultiSelectManager.ownedAssets;
      const motionId = still?.livePhotoVideoId;
      if (!still || !motionId) {
        return;
      }
      try {
        const stillResponse = await updateAsset({ id: still.id, updateAssetDto: { livePhotoVideoId: null } });
        const motionResponse = await getAssetInfo({ ...authManager.params, id: motionId });
        onUnlink?.({ still: toTimelineAsset(stillResponse), motion: toTimelineAsset(motionResponse) });
        assetMultiSelectManager.clear();
      } catch (error) {
        handleError(error, $t('errors.unable_to_unlink_motion_video'));
      }
    },
  };

  const ChangeDate: ActionItem = {
    title: $t('change_date'),
    icon: mdiCalendarEditOutline,
    $if: () => showChangeDate,
    onAction: async () => {
      const assets = assetMultiSelectManager.ownedAssets;
      const initialDate = assets.length === 1 ? fromTimelinePlainDateTime(assets[0].localDateTime) : DateTime.now();
      const success = await modalManager.show(AssetSelectionChangeDateModal, { initialDate, assets });
      if (success) {
        assetMultiSelectManager.clear();
      }
    },
  };

  const ChangeDescription: ActionItem = {
    title: $t('change_description'),
    icon: mdiText,
    $if: () => showChangeDescription,
    onAction: async () => {
      const description = await modalManager.show(AssetUpdateDescriptionConfirmModal);
      if (!description) {
        return;
      }
      const ids = getOwnedAssetsWithWarning(assetMultiSelectManager.assets, get(user));
      try {
        await updateAssets({ assetBulkUpdateDto: { ids, description } });
        assetMultiSelectManager.clear();
      } catch (error) {
        handleError(error, $t('errors.unable_to_change_description'));
      }
    },
  };

  const ChangeLocation: ActionItem = {
    title: $t('change_location'),
    icon: mdiMapMarkerMultipleOutline,
    $if: () => showChangeLocation,
    onAction: async () => {
      const point = await modalManager.show(GeolocationPointPickerModal, {});
      if (!point) {
        return;
      }
      const ids = getOwnedAssetsWithWarning(assetMultiSelectManager.assets, get(user));
      try {
        await updateAssets({ assetBulkUpdateDto: { ids, latitude: point.lat, longitude: point.lng } });
        toastManager.primary($t('edit_location_action_prompt', { values: { count: ids.length } }));
        assetMultiSelectManager.clear();
      } catch (error) {
        handleError(error, $t('errors.unable_to_update_location'));
      }
    },
  };

  const Archive: ActionItem = {
    title: unarchive ? $t('unarchive') : $t('to_archive'),
    icon: unarchive ? mdiArchiveArrowUpOutline : mdiArchiveArrowDownOutline,
    $if: () => showArchive,
    onAction: async () => {
      const visibility = unarchive ? AssetVisibility.Timeline : AssetVisibility.Archive;
      const assets = assetMultiSelectManager.getOwnedAssets().filter((asset) => asset.visibility !== visibility);
      const ids = await archiveAssets(assets, visibility);
      if (ids) {
        onArchive?.(ids, visibility);
        assetMultiSelectManager.clear();
      }
    },
  };

  const Tag: ActionItem = {
    title: $t('tag'),
    icon: mdiTagMultipleOutline,
    $if: () => showTag && get(preferences).tags.enabled,
    onAction: async () => {
      const assets = assetMultiSelectManager.ownedAssets;
      const didUpdate = await modalManager.show(AssetTagModal, { assetIds: assets.map(({ id }) => id) });
      if (didUpdate) {
        assetMultiSelectManager.clear();
      }
    },
  };

  const Delete: ActionItem = {
    title: forceDelete || !featureFlagsManager.value.trash ? $t('permanently_delete') : $t('delete'),
    icon: mdiTrashCanOutline,
    $if: () => showDelete,
    onAction: async () => {
      const assets = assetMultiSelectManager.ownedAssets;
      const force = forceDelete || !featureFlagsManager.value.trash;
      if (get(showDeleteModal)) {
        const confirmed = await modalManager.show(AssetDeleteConfirmModal, { size: assets.length });
        if (!confirmed) {
          return;
        }
      }
      await deleteAssets(force, onAssetDelete, assets, onUndoDelete);
      assetMultiSelectManager.clear();
    },
  };

  const SetVisibility: ActionItem = {
    title: unlock ? $t('move_off_locked_folder') : $t('move_to_locked_folder'),
    icon: unlock ? mdiLockOpenVariantOutline : mdiLockOutline,
    $if: () => showVisibility && !!onVisibilitySet,
    onAction: async () => {
      const isConfirmed = await modalManager.showDialog({
        title: unlock ? $t('remove_from_locked_folder') : $t('move_to_locked_folder'),
        prompt: unlock ? $t('remove_from_locked_folder_confirmation') : $t('move_to_locked_folder_confirmation'),
        confirmText: $t('move'),
        confirmColor: unlock ? 'danger' : 'primary',
        icon: unlock ? mdiLockOpenVariantOutline : mdiLockOutline,
      });
      if (!isConfirmed) {
        return;
      }
      try {
        const assetIds = assetMultiSelectManager.assets.map(({ id }) => id);
        await updateAssets({
          assetBulkUpdateDto: {
            ids: assetIds,
            visibility: unlock ? AssetVisibility.Timeline : AssetVisibility.Locked,
          },
        });
        onVisibilitySet?.(assetIds);
      } catch (error) {
        handleError(error, $t('errors.unable_to_save_settings'));
      }
    },
  };

  const items: MenuItems = [
    Slideshow,
    showAddToAlbum ? Jobs.AddToAlbum : undefined,
    Download,
    Stack,
    Unstack,
    LinkLivePhoto,
    UnlinkLivePhoto,
    ChangeDate,
    ChangeDescription,
    ChangeLocation,
    Archive,
    Tag,
    SetVisibility,
    Delete,
    ...extraItems,
  ];

  if (showJobs) {
    items.push(
      MenuItemType.Divider,
      {
        ...Jobs.RegenerateThumbnailJob,
        icon: mdiImageRefreshOutline,
      },
      {
        ...Jobs.RefreshMetadataJob,
        icon: mdiDatabaseRefreshOutline,
      },
      {
        ...Jobs.TranscodeVideoJob,
        icon: mdiCogRefreshOutline,
      },
    );
  }

  return items;
};

const isSingleStackedAssetSelected = () => {
  const assets = assetMultiSelectManager.ownedAssets;
  return assets.length === 1 && !!assets[0].stack;
};
