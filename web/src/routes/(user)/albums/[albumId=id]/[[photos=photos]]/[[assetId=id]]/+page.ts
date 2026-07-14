import { Route } from '$lib/route';
import { albumPreviousRoute } from '$lib/stores/navigation.store';
import { authenticate } from '$lib/utils/auth';
import { getAlbumInfo, type AlbumResponseDto } from '@immich/sdk';
import { redirect } from '@sveltejs/kit';
import { get } from 'svelte/store';
import type { PageLoad } from './$types';

export const load = (async ({ params, url }) => {
  await authenticate(url);

  let album: AlbumResponseDto;

  try {
    album = await getAlbumInfo({ id: params.albumId, withoutAssets: true });
  } catch (error) {
    const prev = get(albumPreviousRoute);

    if (!prev) {
      redirect(302, Route.albums());
    }

    redirect(302, prev);
  }

  return {
    album,
    meta: {
      title: album.albumName,
    },
  };
}) satisfies PageLoad;
