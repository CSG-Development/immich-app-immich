import { getServerErrorMessage } from '$lib/utils/handle-error';
import { AlbumUserRole, getAlbumInfo, type AlbumResponseDto, type UserResponseDto } from '@immich/sdk';

export type AlbumEditAccessResult =
  | { kind: 'allowed'; album: AlbumResponseDto }
  | { kind: 'view_only'; album: AlbumResponseDto }
  | { kind: 'access_denied' }
  | { kind: 'deleted' };

/** First albumUsers entry is always the album owner (SDK contract since v3). */
export const getAlbumOwner = (album: AlbumResponseDto): UserResponseDto | undefined => album.albumUsers[0]?.user;

export const getAlbumOwnerId = (album: AlbumResponseDto): string | undefined => getAlbumOwner(album)?.id;

export const isAlbumEditor = (album: AlbumResponseDto, userId: string): boolean =>
  getAlbumOwnerId(album) === userId ||
  album.albumUsers.some(({ user, role }) => user.id === userId && role === AlbumUserRole.Editor);

export const classifyAlbumAccessError = (error: unknown): 'access_denied' | 'deleted' => {
  const message = getServerErrorMessage(error) ?? '';
  if (/album has been deleted|album not found/i.test(message)) {
    return 'deleted';
  }
  return 'access_denied';
};

export const isAlbumPermissionError = (error: unknown): boolean => {
  const message = getServerErrorMessage(error) ?? '';
  return /album\.read|albumAsset\.create|album has been deleted|album not found/i.test(message);
};

export const checkAlbumEditAccess = async (albumId: string, userId: string): Promise<AlbumEditAccessResult> => {
  try {
    const album = await getAlbumInfo({ id: albumId });
    if (isAlbumEditor(album, userId)) {
      return { kind: 'allowed', album };
    }
    return { kind: 'view_only', album };
  } catch (error) {
    return { kind: classifyAlbumAccessError(error) };
  }
};

export const albumAccessMessageKey = (
  result: Exclude<AlbumEditAccessResult, { kind: 'allowed' }>,
): 'album_permissions_changed_view_only' | 'album_access_denied' | 'album_deleted_by_owner' => {
  switch (result.kind) {
    case 'view_only': {
      return 'album_permissions_changed_view_only';
    }
    case 'access_denied': {
      return 'album_access_denied';
    }
    case 'deleted': {
      return 'album_deleted_by_owner';
    }
  }
};
