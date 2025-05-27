import { resolveRoute } from '$app/paths';
import { AppRoute } from '$lib/constants';
import { redirect } from '@sveltejs/kit';
import type { PageLoad } from './$types';

export const load = (() => {
  redirect(302, resolveRoute(AppRoute.PHOTOS, {}));
}) satisfies PageLoad;
