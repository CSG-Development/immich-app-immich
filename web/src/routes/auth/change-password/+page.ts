import { resolveRoute } from '$app/paths';
import { AppRoute } from '$lib/constants';
import { user } from '$lib/stores/user.store';
import { authenticate } from '$lib/utils/auth';
import { getFormatter } from '$lib/utils/i18n';
import { redirect } from '@sveltejs/kit';
import { get } from 'svelte/store';
import type { PageLoad } from './$types';

export const load = (async ({ url }) => {
  await authenticate(url);
  if (!get(user).shouldChangePassword) {
    redirect(302, resolveRoute(AppRoute.PHOTOS, {}));
  }

  const $t = await getFormatter();

  return {
    meta: {
      title: $t('change_password'),
    },
  };
}) satisfies PageLoad;
