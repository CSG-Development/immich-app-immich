import { goto } from '$app/navigation';
import { sdkMock } from '$lib/__mocks__/sdk.mock';
import { eventManager } from '$lib/managers/event-manager.svelte';
import { Route } from '$lib/route';
import { getAlbumActions, handleLeaveAlbum } from '$lib/services/album.service';
import { user as userStore } from '$lib/stores/user.store';
import { getFormatter } from '$lib/utils/i18n';
import { AlbumUserRole } from '@immich/sdk';
import { toastManager } from '@immich/ui';
import { albumFactory } from '@test-data/factories/album-factory';
import { userAdminFactory, userFactory } from '@test-data/factories/user-factory';

vi.mock('$app/navigation', () => ({
  goto: vi.fn(),
}));

vi.mock('$lib/utils/i18n', () => ({
  getFormatter: vi.fn(),
  getPreferredLocale: vi.fn(),
}));

vi.mock('@immich/ui', () => ({
  toastManager: {
    primary: vi.fn(),
    danger: vi.fn(),
    warning: vi.fn(),
    info: vi.fn(),
  },
  modalManager: {
    show: vi.fn(),
    showDialog: vi.fn(),
    open: vi.fn(),
  },
}));

vi.mock('$lib/modals/AlbumAddUsersModal.svelte', () => ({ default: {} }));
vi.mock('$lib/modals/AlbumOptionsModal.svelte', () => ({ default: {} }));
vi.mock('$lib/modals/SharedLinkCreateModal.svelte', () => ({ default: {} }));
vi.mock('$lib/utils/handle-error', () => ({
  handleError: vi.fn(),
  getServerErrorMessage: vi.fn(),
}));

describe('AlbumService', () => {
  const owner = userAdminFactory.build();
  const editor = userAdminFactory.build();
  const viewer = userAdminFactory.build();
  const $t = vi.fn((key: string) => key);

  const sharedAlbum = () =>
    albumFactory.build({
      ownerId: owner.id,
      owner: userFactory.build({ id: owner.id, name: owner.name }),
      albumUsers: [
        { user: userFactory.build({ id: editor.id, name: editor.name }), role: AlbumUserRole.Editor },
        { user: userFactory.build({ id: viewer.id, name: viewer.name }), role: AlbumUserRole.Viewer },
      ],
    });

  beforeEach(() => {
    vi.clearAllMocks();
    vi.mocked(getFormatter).mockResolvedValue($t);
  });

  describe('getAlbumActions', () => {
    it('hides invite and shared-link actions for viewers', () => {
      userStore.set(viewer);
      const { AddUsers, CreateSharedLink, Share } = getAlbumActions($t, sharedAlbum());

      expect(AddUsers.$if?.()).toBe(false);
      expect(CreateSharedLink.$if?.()).toBe(false);
      expect(Share.$if?.()).toBe(false);
    });

    it('keeps invite and shared-link actions for editors', () => {
      userStore.set(editor);
      const { AddUsers, CreateSharedLink, Share } = getAlbumActions($t, sharedAlbum());

      expect(AddUsers.$if?.()).toBe(true);
      expect(CreateSharedLink.$if?.()).toBe(true);
      expect(Share.$if?.()).toBe(false);
    });

    it('keeps invite, shared-link, and share actions for owners', () => {
      userStore.set(owner);
      const { AddUsers, CreateSharedLink, Share } = getAlbumActions($t, sharedAlbum());

      expect(AddUsers.$if?.()).toBe(true);
      expect(CreateSharedLink.$if?.()).toBe(true);
      expect(Share.$if?.()).toBe(true);
    });
  });

  describe('handleLeaveAlbum', () => {
    it('removes the current user, shows a success toast, and redirects without an access error', async () => {
      const album = sharedAlbum();
      userStore.set(viewer);
      sdkMock.removeUserFromAlbum.mockResolvedValue(undefined);
      const emitSpy = vi.spyOn(eventManager, 'emit');

      await expect(handleLeaveAlbum(album)).resolves.toBe(true);

      expect(sdkMock.removeUserFromAlbum).toHaveBeenCalledWith({ id: album.id, userId: 'me' });
      expect(emitSpy).toHaveBeenCalledWith('AlbumUserDelete', {
        albumId: album.id,
        userId: viewer.id,
        selfLeft: true,
      });
      expect($t).toHaveBeenCalledWith('you_left_the_album');
      expect(toastManager.primary).toHaveBeenCalledWith('you_left_the_album');
      expect(goto).toHaveBeenCalledWith(Route.albums());
    });

    it('does not redirect or emit when leaving fails', async () => {
      const album = sharedAlbum();
      userStore.set(editor);
      sdkMock.removeUserFromAlbum.mockRejectedValue(new Error('failed'));
      const emitSpy = vi.spyOn(eventManager, 'emit');

      await expect(handleLeaveAlbum(album)).resolves.toBe(false);

      expect(emitSpy).not.toHaveBeenCalledWith(
        'AlbumUserDelete',
        expect.objectContaining({ albumId: album.id, selfLeft: true }),
      );
      expect(goto).not.toHaveBeenCalled();
    });
  });
});
