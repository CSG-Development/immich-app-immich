import {
  albumAccessMessageKey,
  checkAlbumEditAccess,
  classifyAlbumAccessError,
  isAlbumEditor,
  isAlbumPermissionError,
} from '$lib/utils/album-access';
import { AlbumUserRole, getAlbumInfo, type AlbumResponseDto } from '@immich/sdk';
import { albumFactory } from '@test-data/factories/album-factory';
import { userFactory } from '@test-data/factories/user-factory';

vi.mock('@immich/sdk', async (importOriginal) => {
  const actual = await importOriginal<typeof import('@immich/sdk')>();
  return {
    ...actual,
    getAlbumInfo: vi.fn(),
  };
});

vi.mock('$lib/utils/handle-error', () => ({
  getServerErrorMessage: (error: unknown) => {
    if (error && typeof error === 'object' && 'data' in error) {
      return (error as { data?: { message?: string } }).data?.message;
    }
    return undefined;
  },
}));

describe('album-access utils', () => {
  const owner = userFactory.build();
  const editor = userFactory.build();
  const viewer = userFactory.build();

  const sharedAlbum = (): AlbumResponseDto =>
    albumFactory.build({
      ownerId: owner.id,
      albumUsers: [
        { user: editor, role: AlbumUserRole.Editor },
        { user: viewer, role: AlbumUserRole.Viewer },
      ],
    });

  beforeEach(() => {
    vi.mocked(getAlbumInfo).mockReset();
  });

  describe('isAlbumEditor', () => {
    it('returns true for the album owner', () => {
      expect(isAlbumEditor(sharedAlbum(), owner.id)).toBe(true);
    });

    it('returns true for editors', () => {
      expect(isAlbumEditor(sharedAlbum(), editor.id)).toBe(true);
    });

    it('returns false for viewers', () => {
      expect(isAlbumEditor(sharedAlbum(), viewer.id)).toBe(false);
    });
  });

  describe('classifyAlbumAccessError', () => {
    it('detects deleted albums', () => {
      expect(classifyAlbumAccessError({ data: { message: 'Album has been deleted' } })).toBe('deleted');
      expect(classifyAlbumAccessError({ data: { message: 'Album not found' } })).toBe('deleted');
    });

    it('defaults to access denied', () => {
      expect(classifyAlbumAccessError({ data: { message: 'Not found or no album.read access' } })).toBe(
        'access_denied',
      );
    });
  });

  describe('isAlbumPermissionError', () => {
    it('matches album permission messages', () => {
      expect(isAlbumPermissionError({ data: { message: 'Not found or no albumAsset.create access' } })).toBe(true);
      expect(isAlbumPermissionError({ data: { message: 'Not found or no album.read access' } })).toBe(true);
      expect(isAlbumPermissionError({ data: { message: 'Album has been deleted' } })).toBe(true);
      expect(isAlbumPermissionError({ data: { message: 'Something else' } })).toBe(false);
    });
  });

  describe('albumAccessMessageKey', () => {
    it('maps results to i18n keys', () => {
      const album = sharedAlbum();
      expect(albumAccessMessageKey({ kind: 'view_only', album })).toBe('album_permissions_changed_view_only');
      expect(albumAccessMessageKey({ kind: 'access_denied' })).toBe('album_access_denied');
      expect(albumAccessMessageKey({ kind: 'deleted' })).toBe('album_deleted_by_owner');
    });
  });

  describe('checkAlbumEditAccess', () => {
    it('returns allowed for editors', async () => {
      const album = sharedAlbum();
      vi.mocked(getAlbumInfo).mockResolvedValue(album);

      await expect(checkAlbumEditAccess(album.id, editor.id)).resolves.toEqual({ kind: 'allowed', album });
    });

    it('returns view_only when permissions were downgraded', async () => {
      const album = sharedAlbum();
      vi.mocked(getAlbumInfo).mockResolvedValue(album);

      await expect(checkAlbumEditAccess(album.id, viewer.id)).resolves.toEqual({ kind: 'view_only', album });
    });

    it('returns access_denied when the album can no longer be read', async () => {
      vi.mocked(getAlbumInfo).mockRejectedValue({ data: { message: 'Not found or no album.read access' } });

      await expect(checkAlbumEditAccess('album-id', editor.id)).resolves.toEqual({ kind: 'access_denied' });
    });

    it('returns deleted when the album was removed', async () => {
      vi.mocked(getAlbumInfo).mockRejectedValue({ data: { message: 'Album has been deleted' } });

      await expect(checkAlbumEditAccess('album-id', editor.id)).resolves.toEqual({ kind: 'deleted' });
    });
  });
});
