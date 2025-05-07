import { resolveRoute } from '$app/paths';
import { AppRoute } from '$lib/constants';
import { redirect } from '@sveltejs/kit';
import type { PageLoad } from './$types';

export const load = (() => {
  redirect(307, resolveRoute(AppRoute.SHARED_LINKS, {}));
}) satisfies PageLoad;
