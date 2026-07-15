import { goto } from '$app/navigation';
import type { OnAction, PreAction } from '$lib/components/asset-viewer/actions/action';
import { AssetAction } from '$lib/constants';
import { eventManager } from '$lib/managers/event-manager.svelte';
import { featureFlagsManager } from '$lib/managers/feature-flags-manager.svelte';
import ProfileImageCropperModal from '$lib/modals/ProfileImageCropperModal.svelte';
import { Route } from '$lib/route';
import { getAssetActions } from '$lib/services/asset.service';
import { getSharedLink } from '$lib/utils';
import { deleteStack, keepThisDeleteOthers, toggleArchive } from '$lib/utils/asset-utils';
import { openFileUploadDialog } from '$lib/utils/file-uploader';
import { handleError } from '$lib/utils/handle-error';
import { toTimelineAsset } from '$lib/utils/timeline-util';
import {
  AssetTypeEnum,
  AssetVisibility,
  createStack,
  getAlbumInfo,
  removeAssetFromAlbum,
  removeAssetFromStack,
  restoreAssets,
  updateAlbumInfo,
  updateAssets,
  updatePerson,
  updateStack,
  type AlbumResponseDto,
  type AssetResponseDto,
  type PersonResponseDto,
  type StackResponseDto,
} from '@immich/sdk';
import { MenuItemType, modalManager, toastManager, type ActionItem, type MenuItems } from '@immich/ui';
import {
  mdiAccountCircleOutline,
  mdiArchiveArrowDownOutline,
  mdiArchiveArrowUpOutline,
  mdiCompare,
  mdiFaceManProfile,
  mdiHistory,
  mdiImageCheckOutline,
  mdiImageMinusOutline,
  mdiImageOffOutline,
  mdiImageOutline,
  mdiImageRemoveOutline,
  mdiImageSearch,
  mdiLockOpenVariantOutline,
  mdiLockOutline,
  mdiPinOutline,
  mdiPresentationPlay,
  mdiUploadMultiple,
  mdiVideoOutline,
} from '@mdi/js';
import type { MessageFormatter } from 'svelte-i18n';

type ViewerMoreMenuOptions = {
  asset: AssetResponseDto;
  album?: AlbumResponseDto | null;
  person?: PersonResponseDto | null;
  stack?: StackResponseDto | null;
  showSlideshow?: boolean;
  isOwner: boolean;
  isAlbumOwner: boolean;
  preAction: PreAction;
  onAction: OnAction;
  onPlaySlideshow: () => void;
  onRemoveFromAlbum?: (assetIds: string[]) => void;
  playOriginalVideo: boolean;
  setPlayOriginalVideo: (value: boolean) => void;
};

export const getAssetViewerMoreMenuItems = ($t: MessageFormatter, options: ViewerMoreMenuOptions): MenuItems => {
  const {
    asset,
    album = null,
    person = null,
    stack = null,
    showSlideshow = false,
    isOwner,
    isAlbumOwner,
    preAction,
    onAction,
    onPlaySlideshow,
    onRemoveFromAlbum,
    playOriginalVideo,
    setPlayOriginalVideo,
  } = options;

  if (getSharedLink()) {
    return [];
  }

  const Actions = getAssetActions($t, asset);
  const isLocked = asset.visibility === AssetVisibility.Locked;
  const smartSearchEnabled = featureFlagsManager.value.smartSearch;

  const Slideshow: ActionItem = {
    title: $t('slideshow'),
    icon: mdiPresentationPlay,
    $if: () => showSlideshow && !isLocked,
    onAction: () => onPlaySlideshow(),
  };

  const Restore: ActionItem = {
    title: $t('restore'),
    icon: mdiHistory,
    $if: () => !isLocked && asset.isTrashed,
    onAction: async () => {
      try {
        await restoreAssets({ bulkIdsDto: { ids: [asset.id] } });
        asset.isTrashed = false;
        onAction({ type: AssetAction.RESTORE, asset: toTimelineAsset(asset) });
        toastManager.primary($t('restored_asset'));
      } catch (error) {
        handleError(error, $t('errors.unable_to_restore_assets'));
      }
    },
  };

  const RemoveFromAlbum: ActionItem = {
    title: $t('remove_from_album'),
    icon: mdiImageRemoveOutline,
    $if: () => !!album && (isOwner || isAlbumOwner),
    onAction: async () => {
      if (!album) {
        return;
      }
      const isConfirmed = await modalManager.showDialog({
        prompt: $t('remove_assets_album_confirmation', { values: { count: 1 } }),
      });
      if (!isConfirmed) {
        return;
      }
      try {
        await removeAssetFromAlbum({ id: album.id, bulkIdsDto: { ids: [asset.id] } });
        await getAlbumInfo({ id: album.id });
        onRemoveFromAlbum?.([asset.id]);
        toastManager.primary($t('assets_removed_count', { values: { count: 1 } }));
      } catch (error) {
        handleError(error, $t('errors.error_removing_assets_from_album'));
      }
    },
  };

  const AddToStack: ActionItem = {
    title: $t('add_upload_to_stack'),
    icon: mdiUploadMultiple,
    $if: () => isOwner,
    onAction: async () => {
      const newAssetIds = await openFileUploadDialog({ multiple: true });
      const primaryAssetId = stack?.primaryAssetId ?? asset.id;
      const newStack = await createStack({ stackCreateDto: { assetIds: [primaryAssetId, ...newAssetIds] } });
      onAction({ type: AssetAction.STACK, stack: newStack });
    },
  };

  const Unstack: ActionItem = {
    title: $t('unstack'),
    icon: mdiImageOffOutline,
    $if: () => isOwner && !!stack,
    onAction: async () => {
      if (!stack) {
        return;
      }
      const unstackedAssets = await deleteStack([stack.id]);
      if (unstackedAssets) {
        onAction({ type: AssetAction.UNSTACK, assets: unstackedAssets.map((item) => toTimelineAsset(item)) });
      }
    },
  };

  const KeepThisDeleteOthers: ActionItem = {
    title: $t('keep_this_delete_others'),
    icon: mdiPinOutline,
    $if: () => isOwner && !!stack,
    onAction: async () => {
      if (!stack) {
        return;
      }
      const isConfirmed = await modalManager.showDialog({
        title: $t('keep_this_delete_others'),
        prompt: $t('confirm_keep_this_delete_others'),
        confirmText: $t('delete_others'),
      });
      if (!isConfirmed) {
        return;
      }
      const keptAsset = await keepThisDeleteOthers(asset, stack);
      if (keptAsset) {
        onAction({ type: AssetAction.UNSTACK, assets: [toTimelineAsset(keptAsset)] });
      }
    },
  };

  const SetStackPrimary: ActionItem = {
    title: $t('set_stack_primary_asset'),
    icon: mdiImageCheckOutline,
    $if: () => isOwner && !!stack && stack.primaryAssetId !== asset.id,
    onAction: async () => {
      if (!stack) {
        return;
      }
      const updatedStack = await updateStack({ id: stack.id, stackUpdateDto: { primaryAssetId: asset.id } });
      if (updatedStack) {
        onAction({ type: AssetAction.SET_STACK_PRIMARY_ASSET, stack: updatedStack });
      }
    },
  };

  const RemoveFromStack: ActionItem = {
    title: $t('viewer_remove_from_stack'),
    icon: mdiImageMinusOutline,
    $if: () => isOwner && !!stack && stack.primaryAssetId !== asset.id && (stack.assets?.length ?? 0) > 2,
    onAction: async () => {
      if (!stack) {
        return;
      }
      await removeAssetFromStack({ id: stack.id, assetId: asset.id });
      onAction({
        type: AssetAction.REMOVE_ASSET_FROM_STACK,
        stack: { ...stack, assets: stack.assets.filter((item) => item.id !== asset.id) },
        asset,
      });
    },
  };

  const SetAlbumCover: ActionItem = {
    title: $t('set_as_album_cover'),
    icon: mdiImageOutline,
    $if: () => !!album,
    onAction: async () => {
      if (!album) {
        return;
      }
      try {
        const response = await updateAlbumInfo({
          id: album.id,
          updateAlbumDto: { albumThumbnailAssetId: asset.id },
        });
        eventManager.emit('AlbumUpdate', response);
        toastManager.primary($t('album_cover_updated'));
      } catch (error) {
        handleError(error, $t('errors.unable_to_update_album_cover'));
      }
    },
  };

  const SetFeaturedPhoto: ActionItem = {
    title: $t('set_as_featured_photo'),
    icon: mdiFaceManProfile,
    $if: () => !!person,
    onAction: async () => {
      if (!person) {
        return;
      }
      try {
        const updatedPerson = await updatePerson({
          id: person.id,
          personUpdateDto: { featureFaceAssetId: asset.id },
        });
        onAction({
          type: AssetAction.SET_PERSON_FEATURED_PHOTO,
          asset,
          person: { ...person, ...updatedPerson },
        });
        toastManager.primary($t('feature_photo_updated'));
      } catch (error) {
        handleError(error, $t('errors.unable_to_set_feature_photo'));
      }
    },
  };

  const SetProfilePicture: ActionItem = {
    title: $t('set_as_profile_picture'),
    icon: mdiAccountCircleOutline,
    $if: () => asset.type === AssetTypeEnum.Image && !isLocked,
    onAction: () => modalManager.show(ProfileImageCropperModal, { asset }),
  };

  const Archive: ActionItem = {
    title: asset.isArchived ? $t('unarchive') : $t('to_archive'),
    icon: asset.isArchived ? mdiArchiveArrowUpOutline : mdiArchiveArrowDownOutline,
    $if: () => !isLocked && isOwner,
    onAction: async () => {
      if (!asset.isArchived) {
        preAction({ type: AssetAction.ARCHIVE, asset: toTimelineAsset(asset) });
      }
      const updatedAsset = await toggleArchive(asset);
      if (updatedAsset) {
        onAction({
          type: asset.isArchived ? AssetAction.ARCHIVE : AssetAction.UNARCHIVE,
          asset: toTimelineAsset(asset),
        });
      }
    },
  };

  const ViewInTimeline: ActionItem = {
    title: $t('view_in_timeline'),
    icon: mdiImageSearch,
    $if: () => !isLocked && isOwner && !asset.isArchived && !asset.isTrashed,
    onAction: () => goto(Route.photos({ at: stack?.primaryAssetId ?? asset.id })),
  };

  const ViewSimilar: ActionItem = {
    title: $t('view_similar_photos'),
    icon: mdiCompare,
    $if: () => !isLocked && !asset.isArchived && !asset.isTrashed && smartSearchEnabled,
    onAction: () => goto(Route.search({ queryAssetId: stack?.primaryAssetId ?? asset.id })),
  };

  const SetVisibility: ActionItem = {
    title:
      asset.visibility === AssetVisibility.Locked ? $t('move_off_locked_folder') : $t('move_to_locked_folder'),
    icon: asset.visibility === AssetVisibility.Locked ? mdiLockOpenVariantOutline : mdiLockOutline,
    $if: () => !asset.isTrashed && isOwner,
    onAction: async () => {
      const locked = asset.visibility === AssetVisibility.Locked;
      const isConfirmed = await modalManager.showDialog({
        title: locked ? $t('remove_from_locked_folder') : $t('move_to_locked_folder'),
        prompt: locked ? $t('remove_from_locked_folder_confirmation') : $t('move_to_locked_folder_confirmation'),
        confirmText: $t('move'),
        confirmColor: locked ? 'danger' : 'primary',
        icon: locked ? mdiLockOpenVariantOutline : mdiLockOutline,
      });
      if (!isConfirmed) {
        return;
      }
      const timelineAsset = toTimelineAsset(asset);
      try {
        preAction({
          type: locked ? AssetAction.SET_VISIBILITY_TIMELINE : AssetAction.SET_VISIBILITY_LOCKED,
          asset: timelineAsset,
        });
        await updateAssets({
          assetBulkUpdateDto: {
            ids: [asset.id],
            visibility: locked ? AssetVisibility.Timeline : AssetVisibility.Locked,
          },
        });
        onAction({
          type: locked ? AssetAction.SET_VISIBILITY_TIMELINE : AssetAction.SET_VISIBILITY_LOCKED,
          asset: timelineAsset,
        });
      } catch (error) {
        handleError(error, $t('errors.unable_to_save_settings'));
      }
    },
  };

  const PlayVideoMode: ActionItem = {
    title: playOriginalVideo ? $t('play_transcoded_video') : $t('play_original_video'),
    icon: mdiVideoOutline,
    $if: () => asset.type === AssetTypeEnum.Video,
    onAction: () => setPlayOriginalVideo(!playOriginalVideo),
  };

  return [
    Slideshow,
    Actions.Download,
    Actions.DownloadOriginal,
    Restore,
    Actions.AddToAlbum,
    RemoveFromAlbum,
    AddToStack,
    Unstack,
    KeepThisDeleteOthers,
    SetStackPrimary,
    RemoveFromStack,
    SetAlbumCover,
    SetFeaturedPhoto,
    SetProfilePicture,
    Archive,
    ViewInTimeline,
    ViewSimilar,
    SetVisibility,
    PlayVideoMode,
    isOwner ? MenuItemType.Divider : undefined,
    isOwner ? Actions.RefreshFacesJob : undefined,
    isOwner ? Actions.RefreshMetadataJob : undefined,
    isOwner ? Actions.RegenerateThumbnailJob : undefined,
    isOwner ? Actions.TranscodeVideoJob : undefined,
  ];
};
