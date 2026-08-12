import { OS } from '$lib/constants';
import type { AssetMultiSelectManager } from '$lib/managers/asset-multi-select-manager.svelte';
import { authManager } from '$lib/managers/auth-manager.svelte';
import { downloadManager } from '$lib/managers/download-manager.svelte';
import { TimelineManager } from '$lib/managers/timeline-manager/timeline-manager.svelte';
import type { TimelineAsset } from '$lib/managers/timeline-manager/types';
import { preferences } from '$lib/stores/user.store';
import { downloadRequest, withError } from '$lib/utils';
import { getByteUnitString } from '$lib/utils/byte-units';
import { getFormatter } from '$lib/utils/i18n';
import { navigate } from '$lib/utils/navigation';
import { asQueryString } from '$lib/utils/shared-links';
import {
  AssetVisibility,
  bulkTagAssets,
  createStack,
  deleteAssets,
  deleteStacks,
  getBaseUrl,
  getDownloadInfo,
  getStack,
  untagAssets,
  updateAsset,
  updateAssets,
  type AssetResponseDto,
  type AssetTypeEnum,
  type DownloadInfoDto,
  type ExifResponseDto,
  type StackResponseDto,
  type UserPreferencesResponseDto,
  type UserResponseDto,
} from '@immich/sdk';
import { toastManager } from '@immich/ui';
import { DateTime } from 'luxon';
import { t } from 'svelte-i18n';
import { get } from 'svelte/store';
import { handleError } from './handle-error';

export const tagAssets = async ({
  assetIds,
  tagIds,
  showNotification = true,
}: {
  assetIds: string[];
  tagIds: string[];
  showNotification?: boolean;
}) => {
  await bulkTagAssets({ tagBulkAssetsDto: { tagIds, assetIds } });

  if (showNotification) {
    const $t = await getFormatter();
    toastManager.primary($t('tagged_assets', { values: { count: assetIds.length } }));
  }

  return assetIds;
};

export const removeTag = async ({
  assetIds,
  tagIds,
  showNotification = true,
}: {
  assetIds: string[];
  tagIds: string[];
  showNotification?: boolean;
}) => {
  for (const tagId of tagIds) {
    await untagAssets({ id: tagId, bulkIdsDto: { ids: assetIds } });
  }

  if (showNotification) {
    const $t = await getFormatter();
    toastManager.primary($t('removed_tagged_assets', { values: { count: assetIds.length } }));
  }

  return assetIds;
};

export const downloadBlob = (data: Blob, filename: string) => {
  const url = URL.createObjectURL(data);

  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;

  document.body.append(anchor);
  anchor.click();
  anchor.remove();

  URL.revokeObjectURL(url);
};

export const downloadUrl = (url: string, filename: string) => {
  const anchor = document.createElement('a');
  anchor.href = url;
  anchor.download = filename;

  document.body.append(anchor);
  anchor.click();
  anchor.remove();

  URL.revokeObjectURL(url);
};

export const downloadArchive = async (fileName: string, options: Omit<DownloadInfoDto, 'archiveSize'>) => {
  const $preferences = get<UserPreferencesResponseDto | undefined>(preferences);
  const dto = { ...options, archiveSize: $preferences?.download.archiveSize };

  const [error, downloadInfo] = await withError(() => getDownloadInfo({ ...authManager.params, downloadInfoDto: dto }));
  if (error) {
    const $t = get(t);
    handleError(error, $t('errors.unable_to_download_files'));
    return;
  }

  if (!downloadInfo) {
    return;
  }

  for (let index = 0; index < downloadInfo.archives.length; index++) {
    const archive = downloadInfo.archives[index];
    const suffix = downloadInfo.archives.length > 1 ? `+${index + 1}` : '';
    const archiveName = fileName.replace('.zip', `${suffix}-${DateTime.now().toFormat('yyyyLLdd_HHmmss')}.zip`);
    const queryParams = asQueryString(authManager.params);

    let downloadKey = `${archiveName} `;
    if (downloadInfo.archives.length > 1) {
      downloadKey = `${archiveName} (${index + 1}/${downloadInfo.archives.length})`;
    }

    const abort = new AbortController();
    downloadManager.add(downloadKey, archive.size, abort);

    try {
      // TODO use sdk once it supports progress events
      const { data } = await downloadRequest({
        method: 'POST',
        url: getBaseUrl() + '/download/archive' + (queryParams ? `?${queryParams}` : ''),
        data: { assetIds: archive.assetIds, edited: true },
        signal: abort.signal,
        onDownloadProgress: (event) => downloadManager.update(downloadKey, event.loaded),
      });

      downloadBlob(data, archiveName);
    } catch (error) {
      const $t = get(t);
      handleError(error, $t('errors.unable_to_download_files'));
      downloadManager.clear(downloadKey);
      return;
    } finally {
      setTimeout(() => downloadManager.clear(downloadKey), 5000);
    }
  }
};

/**
 * Returns the lowercase filename extension without a dot (.) and
 * an empty string when not found.
 */
export function getFilenameExtension(filename: string): string {
  const lastIndex = Math.max(0, filename.lastIndexOf('.'));
  const startIndex = (lastIndex || Number.POSITIVE_INFINITY) + 1;
  return filename.slice(startIndex).toLowerCase();
}

/**
 * Returns the filename of an asset including file extension
 */
export function getAssetFilename(asset: AssetResponseDto): string {
  const fileExtension = getFilenameExtension(asset.originalPath);
  return `${asset.originalFileName}.${fileExtension}`;
}

function isRotated90CW(orientation: number) {
  return orientation === 5 || orientation === 6 || orientation === 90;
}

function isRotated270CW(orientation: number) {
  return orientation === 7 || orientation === 8 || orientation === -90;
}

export function isFlipped(orientation?: string | null) {
  const value = Number(orientation);
  return value && (isRotated270CW(value) || isRotated90CW(value));
}

export const getDimensions = (exifInfo: ExifResponseDto) => {
  const { exifImageWidth: width, exifImageHeight: height } = exifInfo;
  if (isFlipped(exifInfo.orientation)) {
    return { width: height, height: width };
  }

  return { width, height };
};

export function getFileSize(asset: AssetResponseDto, maxPrecision = 4): string {
  const size = asset.exifInfo?.fileSizeInByte || 0;
  return size > 0 ? getByteUnitString(size, undefined, maxPrecision) : 'Invalid Data';
}

export function getAssetResolution(asset: AssetResponseDto): string {
  if (!asset.width || !asset.height) {
    return 'Invalid Data';
  }

  return `${asset.width} x ${asset.height}`;
}

/**
 * Returns aspect ratio for the asset
 */
export function getAssetRatio(asset: AssetResponseDto) {
  return asset.width && asset.height ? asset.width / asset.height : null;
}

// list of supported image extensions from https://developer.mozilla.org/en-US/docs/Web/Media/Formats/Image_types excluding svg
const supportedImageMimeTypes = new Set([
  'image/apng',
  'image/avif',
  'image/bmp',
  'image/gif',
  'image/jpeg',
  'image/png',
  'image/webp',
  'video/3gpp',
  'video/x-msvideo',
  'video/x-flv',
  'video/x-m4v',
  'video/x-matroska',
  'video/mp2t',
  'video/mp4',
  'video/mpeg',
  'video/quicktime',
  'video/webm',
  'video/x-ms-asf',
  'video/x-ms-wmv',
  'video/x-ms-asf',
  'video/x-ms-wm',
  'video/3gpp',
  'video/x-msvideo',
  'video/msvideo',
  'video/avi',
  'video/x-flv',
  'flv-application/octet-stream',
  'video/flv',
  'video/mp2t',
  'video/vnd.dlna.mpeg-tts',
  'video/mpeg',
  'video/x-matroska',
  'video/matroska',
  'video/quicktime',
  'video/x-quicktime',
  'application/quicktime',
  'video/mts',
  'video/avchd-stream',
  'video/vnd.dlna.mpeg-tts',
  'model/vnd.mts',
  'application/mxf',
  'image/x-canon-cr2',
  'image/cr2',
  'image/jp2',
  'image/jpx',
  'image/jpm',
  'image/vnd.adobe.photoshop',
  'image/psd',
  'image/x-panasonic-raw',
  'image/x-panasonic-rw2',
  'image/x-panasonic-raw2',
  'image/svg+xml',
  'image/svg-xml',
  'image/tiff',
  'image/tif',
]);

export const isFirefox = typeof navigator !== 'undefined' && navigator.userAgent.includes('Firefox');

/* const isSafari = /^((?!chrome|android).)*safari/i.test(navigator.userAgent); */ // https://stackoverflow.com/a/23522755
export const getOS = () => {
  const userAgent = navigator.userAgent;

  if (/Windows NT/i.test(userAgent)) {
    return OS.WINDOWS;
  }
  if (/Mac/i.test(userAgent)) {
    return OS.MACOS;
  }
  if (/Linux/i.test(userAgent)) {
    return OS.LINUX;
  }
  if (/Android/i.test(userAgent)) {
    return OS.ANDROID;
  }
  if (/iPhone|iPad|iPod/i.test(userAgent)) {
    return OS.IOS;
  }

  return 'Unknown';
};

/**
 * Returns true if the asset is an image supported by web browsers, false otherwise
 */

export const isHEIC = (file: File): boolean => {
  return file.name.toLowerCase().endsWith('.heic') || file.name.toLowerCase().endsWith('.heif');
};

export function isWebSupportedAssetMimeType(type: string): boolean {
  if (!type) {
    return false;
  }

  return supportedImageMimeTypes.has(type.toLowerCase());
}

export function isWebCompatibleImage(asset: AssetResponseDto): boolean {
  if (!asset.originalMimeType) {
    return false;
  }

  return supportedImageMimeTypes.has(asset.originalMimeType);
}

export const getAssetType = (type: AssetTypeEnum) => {
  switch (type) {
    case 'IMAGE': {
      return 'Photo';
    }
    case 'VIDEO': {
      return 'Video';
    }
    default: {
      return 'Asset';
    }
  }
};

export const getOwnedAssetsWithWarning = (assets: TimelineAsset[], user: UserResponseDto | null): string[] => {
  const ids = [...assets].filter((a) => user && a.ownerId === user.id).map((a) => a.id);

  const numberOfIssues = [...assets].filter((a) => user && a.ownerId !== user.id).length;
  if (numberOfIssues > 0) {
    const $t = get(t);
    toastManager.warning($t('errors.cant_change_metadata_assets_count', { values: { count: numberOfIssues } }));
  }
  return ids;
};

export type StackResponse = {
  stack?: StackResponseDto;
  toDeleteIds: string[];
};

export const stackAssets = async (assets: { id: string }[], showNotification = true): Promise<StackResponse> => {
  if (assets.length < 2) {
    return { stack: undefined, toDeleteIds: [] };
  }

  const $t = get(t);

  try {
    const stack = await createStack({ stackCreateDto: { assetIds: assets.map(({ id }) => id) } });
    if (showNotification) {
      toastManager.primary({
        description: $t('stacked_assets_count', { values: { count: stack.assets.length } }),
        button: {
          label: $t('view_stack'),
          onclick: () => navigate({ targetRoute: 'current', assetId: stack.primaryAssetId }),
        },
      });
    }

    return {
      stack,
      toDeleteIds: assets.slice(1).map((asset) => asset.id),
    };
  } catch (error) {
    handleError(error, $t('errors.failed_to_stack_assets'));
    return { stack: undefined, toDeleteIds: [] };
  }
};

export const deleteStack = async (stackIds: string[]) => {
  const ids = [...new Set(stackIds)];
  if (ids.length === 0) {
    return;
  }

  const $t = get(t);

  try {
    const stacks = await Promise.all(ids.map((id) => getStack({ id })));
    const count = stacks.reduce((sum, stack) => sum + stack.assets.length, 0);

    await deleteStacks({ bulkIdsDto: { ids: [...ids] } });

    toastManager.primary($t('unstacked_assets_count', { values: { count } }));

    const assets = stacks.flatMap((stack) => stack.assets);
    for (const asset of assets) {
      asset.stack = null;
    }

    return assets;
  } catch (error) {
    handleError(error, $t('errors.failed_to_unstack_assets'));
  }
};

export const keepThisDeleteOthers = async (keepAsset: AssetResponseDto, stack: StackResponseDto) => {
  const $t = get(t);

  try {
    const assetsToDeleteIds = stack.assets.filter((asset) => asset.id !== keepAsset.id).map((asset) => asset.id);
    await deleteAssets({ assetBulkDeleteDto: { ids: assetsToDeleteIds } });
    await deleteStacks({ bulkIdsDto: { ids: [stack.id] } });

    toastManager.primary($t('kept_this_deleted_others', { values: { count: assetsToDeleteIds.length } }));

    keepAsset.stack = null;
    return keepAsset;
  } catch (error) {
    handleError(error, $t('errors.failed_to_keep_this_delete_others'));
  }
};

export const selectAllAssets = async (timelineManager: TimelineManager, assetInteraction: AssetMultiSelectManager) => {
  if (assetInteraction.selectAll) {
    // Selection is already ongoing
    return;
  }
  assetInteraction.selectAll = true;

  try {
    for (const timelineMonth of timelineManager.months) {
      if (!timelineMonth.isLoaded) {
        await timelineManager.loadTimelineMonth(timelineMonth.yearMonth);
      }

      if (!assetInteraction.selectAll) {
        assetInteraction.clear();
        break; // Cancelled
      }
      assetInteraction.selectAssets([...timelineMonth.assetsIterator()]);

      for (const dateGroup of timelineMonth.timelineDays) {
        assetInteraction.addGroupToMultiselectGroup(dateGroup.groupTitle);
      }
    }
  } catch (error) {
    const $t = get(t);
    handleError(error, $t('errors.error_selecting_all_assets'));
    assetInteraction.selectAll = false;
  }
};

export const toggleArchive = async (asset: AssetResponseDto) => {
  const $t = get(t);
  try {
    const data = await updateAsset({
      id: asset.id,
      updateAssetDto: {
        visibility: asset.isArchived ? AssetVisibility.Timeline : AssetVisibility.Archive,
      },
    });

    asset.isArchived = data.isArchived;
    toastManager.primary(asset.isArchived ? $t(`added_to_archive`) : $t(`removed_from_archive`));
  } catch (error) {
    handleError(error, $t('errors.unable_to_add_remove_archive', { values: { archived: asset.isArchived } }));
  }

  return asset;
};

export const archiveAssets = async (assets: { id: string }[], visibility: AssetVisibility) => {
  const ids = assets.map(({ id }) => id);
  const $t = get(t);

  try {
    if (ids.length > 0) {
      await updateAssets({
        assetBulkUpdateDto: { ids, visibility },
      });
    }

    toastManager.primary(
      visibility === AssetVisibility.Archive
        ? $t('archived_count', { values: { count: ids.length } })
        : $t('unarchived_count', { values: { count: ids.length } }),
    );
  } catch (error) {
    handleError(
      error,
      $t('errors.unable_to_archive_unarchive', { values: { archived: visibility === AssetVisibility.Archive } }),
    );
  }

  return ids;
};

export const delay = async (ms: number) => {
  return new Promise((resolve) => setTimeout(resolve, ms));
};

export const getNextAsset = (assets: AssetResponseDto[], currentAsset: AssetResponseDto | undefined) => {
  const index = currentAsset ? assets.findIndex((a) => a.id === currentAsset.id) : -1;
  return index >= 0 ? assets[index + 1] : undefined;
};

export const getPreviousAsset = (assets: AssetResponseDto[], currentAsset: AssetResponseDto | undefined) => {
  const index = currentAsset ? assets.findIndex((a) => a.id === currentAsset.id) : -1;
  return index >= 0 ? assets[index - 1] : undefined;
};

export const canCopyImageToClipboard = (): boolean => {
  return !!(navigator.clipboard && globalThis.ClipboardItem);
};

export const getFileExtension = (fileName: string) => {
  const dotIndex = fileName.lastIndexOf('.');
  return dotIndex === -1 ? '' : fileName.slice(dotIndex);
};

export const makeImageUnique = (imageElement: HTMLImageElement): HTMLCanvasElement => {
  const canvas = document.createElement('canvas');
  const ctx = canvas.getContext('2d')!;

  canvas.width = imageElement.naturalWidth;
  canvas.height = imageElement.naturalHeight;

  ctx.drawImage(imageElement, 0, 0);

  const width = canvas.width;
  const height = canvas.height;

  if (width < 2 || height < 2) {
    return canvas;
  }

  const ts = Date.now(); // timestamp for some variability

  const points = [
    [width - 1, 0],
    [0, height - 1],
    [ts % width, ts % height],
  ];

  const imageData = ctx.getImageData(0, 0, width, height);
  const data = imageData.data;

  for (const [xRaw, yRaw] of points) {
    const x = Math.min(Math.max(xRaw, 0), width - 1);
    const y = Math.min(Math.max(yRaw, 0), height - 1);

    const r = ts % 256;
    const g = (ts * 3) % 256;
    const b = (ts * 7) % 256;
    const a = 255;

    const index = (y * width + x) * 4;
    data[index] = r;
    data[index + 1] = g;
    data[index + 2] = b;
    data[index + 3] = a;
  }

  ctx.putImageData(imageData, 0, 0);

  return canvas;
};

export const canvasToBlob = async (canvas: HTMLCanvasElement) => {
  return await new Promise<Blob>((resolve, reject) => {
    canvas.toBlob((blob) => {
      if (blob) {
        resolve(blob);
      } else {
        reject(new Error('Canvas conversion to Blob failed'));
      }
    });
  });
};

export const imgToBlob = async (imageElement: HTMLImageElement) => {
  const canvas = document.createElement('canvas');
  const context = canvas.getContext('2d');

  canvas.width = imageElement.naturalWidth;
  canvas.height = imageElement.naturalHeight;

  if (context) {
    context.drawImage(imageElement, 0, 0);

    return await new Promise<Blob>((resolve) => {
      canvas.toBlob((blob) => {
        if (blob) {
          resolve(blob);
        } else {
          throw new Error('Canvas conversion to Blob failed');
        }
      });
    });
  }

  throw new Error('Canvas context is null');
};

export const urlToArrayBuffer = async (imageSource: string) => {
  const response = await fetch(imageSource);
  return await response.arrayBuffer();
};

export const copyImageToClipboard = async (source: HTMLImageElement) => {
  // do not await, so the Safari clipboard write happens in the context of the user gesture
  await navigator.clipboard.write([new ClipboardItem({ ['image/png']: imgToBlob(source) })]);
};

export const navigateToAsset = async (targetAsset: AssetResponseDto | undefined | null) => {
  if (!targetAsset) {
    return false;
  }

  await navigate({ targetRoute: 'current', assetId: targetAsset.id });
  return true;
};
