import { resolve } from '$app/paths';
import { AppRoute } from '$lib/constants';
import { redirect } from '@sveltejs/kit';
import type { PageLoad } from './$types';

export const load = (() => {
  redirect(307, resolve(AppRoute.SHARED_LINKS));
}) satisfies PageLoad;
