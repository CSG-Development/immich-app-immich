import { Route } from '$lib/route';
import { authenticate } from '$lib/utils/auth';
import { getAlbumInfo, type AlbumResponseDto } from '@immich/sdk';
import { redirect } from '@sveltejs/kit';
import type { PageLoad } from './$types';

export const load = (async ({ params, url, depends }) => {
  await authenticate(url);

  depends('album:data');

  let album: AlbumResponseDto;

  try {
    album = await getAlbumInfo({ id: params.albumId, withoutAssets: true });
  } catch {
    // Always leave the album route on failure. Redirecting to a persisted "previous"
    // album URL can re-enter this load and cause a redirect loop.
    redirect(302, Route.albums());
  }

  return {
    album,
    meta: {
      title: album.albumName,
    },
  };
}) satisfies PageLoad;
