import { resolve } from '$app/paths';
import { AppRoute } from '$lib/constants';
import { albumPreviousRoute } from '$lib/stores/navigation.store';
import { authenticate } from '$lib/utils/auth';
import { getAssetInfoFromParam } from '$lib/utils/navigation';
import { getAlbumInfo, type AlbumResponseDto, type AssetResponseDto } from '@immich/sdk';
import { redirect } from '@sveltejs/kit';
import { get } from 'svelte/store';
import type { PageLoad } from './$types';

export const load = (async ({ params, url }) => {
  await authenticate(url);

  let album: AlbumResponseDto;
  let asset: AssetResponseDto | undefined;

  try {
    [album, asset] = await Promise.all([
      getAlbumInfo({ id: params.albumId, withoutAssets: true }),
      getAssetInfoFromParam(params),
    ]);
  } catch (error) {
    const prev = get(albumPreviousRoute);

    if (!prev) {
      redirect(302, resolve(AppRoute.PHOTOS));
    }

    redirect(302, prev);
  }

  return {
    album,
    asset,
    meta: {
      title: album.albumName,
    },
  };
}) satisfies PageLoad;
