import { render, screen } from '@testing-library/svelte';
import { tick } from 'svelte';
import { Route } from '$lib/route';
import { sdkMock } from '$lib/__mocks__/sdk.mock';
import RecentAlbums from '$lib/components/shared-components/side-bar/RecentAlbums.svelte';
import { albumFactory } from '@test-data/factories/album-factory';

describe('RecentAlbums component', () => {
  it('sorts albums by most recently updated', async () => {
    const albums = [
      albumFactory.build({ updatedAt: '2024-01-01T00:00:00Z' }),
      albumFactory.build({ updatedAt: '2024-01-09T00:00:01Z' }),
      albumFactory.build({ updatedAt: '2024-01-10T00:00:00Z' }),
      albumFactory.build({ updatedAt: '2024-01-09T00:00:00Z' }),
    ];

    sdkMock.getAllAlbums.mockResolvedValueOnce([...albums]);
    render(RecentAlbums);

    expect(sdkMock.getAllAlbums).toHaveBeenCalledOnce();

    // wtf
    await tick();
    await tick();

    const links = screen.getAllByRole('link');
    expect(links).toHaveLength(3);
    expect(links[0]).toHaveAttribute('href', Route.viewAlbum(albums[2]));
    expect(links[1]).toHaveAttribute('href', Route.viewAlbum(albums[1]));
    expect(links[2]).toHaveAttribute('href', Route.viewAlbum(albums[3]));
  });
});
