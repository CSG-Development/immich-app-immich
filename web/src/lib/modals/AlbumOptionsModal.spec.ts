import { getAnimateMock } from '$lib/__mocks__/animate.mock';
import { getIntersectionObserverMock } from '$lib/__mocks__/intersection-observer.mock';
import { sdkMock } from '$lib/__mocks__/sdk.mock';
import { getVisualViewportMock } from '$lib/__mocks__/visual-viewport.mock';
import AlbumOptionsModal from '$lib/modals/AlbumOptionsModal.svelte';
import { confirmLeaveAlbum, handleLeaveAlbum } from '$lib/services/album.service';
import { user as userStore } from '$lib/stores/user.store';
import { AlbumUserRole } from '@immich/sdk';
import { albumFactory } from '@test-data/factories/album-factory';
import { userAdminFactory, userFactory } from '@test-data/factories/user-factory';
import { render, screen, waitFor, within } from '@testing-library/svelte';
import userEvent from '@testing-library/user-event';

vi.mock('$lib/services/album.service', async (importOriginal) => {
  const actual = await importOriginal<typeof import('$lib/services/album.service')>();
  return {
    ...actual,
    confirmLeaveAlbum: vi.fn(),
    handleLeaveAlbum: vi.fn(),
  };
});

describe('AlbumOptionsModal', () => {
  const owner = userAdminFactory.build();
  const editor = userAdminFactory.build();
  const viewer = userAdminFactory.build();
  const onClose = vi.fn();

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
    vi.stubGlobal('IntersectionObserver', getIntersectionObserverMock());
    vi.stubGlobal('visualViewport', getVisualViewportMock());
    vi.resetAllMocks();
    Element.prototype.animate = getAnimateMock();
    sdkMock.getAllSharedLinks.mockResolvedValue([]);
  });

  afterAll(async () => {
    await waitFor(() => {
      expect(document.body.style.pointerEvents).not.toBe('none');
    });
  });

  it('hides administrative controls for viewers and shows leave album', async () => {
    userStore.set(viewer);
    render(AlbumOptionsModal, { album: sharedAlbum(), onClose });

    expect(await screen.findByRole('button', { name: 'leave_album' })).toBeInTheDocument();
    expect(screen.queryByText('display_order')).not.toBeInTheDocument();
    expect(screen.queryByText('comments_and_likes')).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'invite_people' })).not.toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'create_link' })).not.toBeInTheDocument();
    expect(screen.queryByText('remove_user')).not.toBeInTheDocument();
  });

  it('keeps album modification controls for editors and shows leave album', async () => {
    userStore.set(editor);
    render(AlbumOptionsModal, { album: sharedAlbum(), onClose });

    expect(await screen.findByText('display_order')).toBeInTheDocument();
    expect(screen.getByText('comments_and_likes')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'invite_people' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'create_link' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'leave_album' })).toBeInTheDocument();
  });

  it('keeps administrative controls for owners and hides leave album', async () => {
    userStore.set(owner);
    render(AlbumOptionsModal, { album: sharedAlbum(), onClose });

    expect(await screen.findByText('display_order')).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'invite_people' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'create_link' })).toBeInTheDocument();
    expect(screen.queryByRole('button', { name: 'leave_album' })).not.toBeInTheDocument();
  });

  it('closes immediately and leaves the album after confirmation', async () => {
    const album = sharedAlbum();
    userStore.set(viewer);
    vi.mocked(confirmLeaveAlbum).mockResolvedValue(true);
    vi.mocked(handleLeaveAlbum).mockResolvedValue(true);

    render(AlbumOptionsModal, { album, onClose });

    await userEvent.click(await screen.findByRole('button', { name: 'leave_album' }));

    expect(confirmLeaveAlbum).toHaveBeenCalledWith(album);
    expect(onClose).toHaveBeenCalled();
    expect(handleLeaveAlbum).toHaveBeenCalledWith(album);
    expect(onClose.mock.invocationCallOrder[0]).toBeLessThan(vi.mocked(handleLeaveAlbum).mock.invocationCallOrder[0]);
  });

  it('does not leave or close when the confirmation is cancelled', async () => {
    userStore.set(editor);
    vi.mocked(confirmLeaveAlbum).mockResolvedValue(false);

    render(AlbumOptionsModal, { album: sharedAlbum(), onClose });

    await userEvent.click(await screen.findByRole('button', { name: 'leave_album' }));

    expect(onClose).not.toHaveBeenCalled();
    expect(handleLeaveAlbum).not.toHaveBeenCalled();
  });

  it('shows every user role option when the sharing dropdown is opened', async () => {
    userStore.set(owner);
    const album = sharedAlbum();
    render(AlbumOptionsModal, { album, onClose });

    const editorRow = (await screen.findByText(editor.name)).closest('div.flex.min-w-0.items-center.gap-4');
    expect(editorRow).toBeTruthy();

    await userEvent.click(within(editorRow as HTMLElement).getByRole('combobox'));

    expect(await screen.findByRole('option', { name: 'role_editor' })).toBeVisible();
    expect(screen.getByRole('option', { name: 'role_viewer' })).toBeVisible();
    expect(screen.getByRole('option', { name: 'remove_user' })).toBeVisible();
  });

  it('truncates a long shared user name and keeps the role control in the row', async () => {
    const longName = 'test11'.repeat(40);
    const longNamedUser = userFactory.build({ name: longName });
    userStore.set(owner);
    render(AlbumOptionsModal, {
      album: albumFactory.build({
        ownerId: owner.id,
        owner: userFactory.build({ id: owner.id, name: owner.name }),
        albumUsers: [{ user: longNamedUser, role: AlbumUserRole.Editor }],
      }),
      onClose,
    });

    const name = await screen.findByText(longName);
    expect(name).toHaveClass('truncate');

    const row = name.closest('div.flex.min-w-0.items-center.gap-4') as HTMLElement;
    expect(within(row).getByRole('combobox')).toBeInTheDocument();
  });
});
