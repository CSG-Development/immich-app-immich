import { authenticate } from '$lib/utils/auth';
import { getFormatter } from '$lib/utils/i18n';
import { getConfig, getSessions } from '@immich/sdk';
import type { PageLoad } from './$types';

export const load = (async ({ url }) => {
  await authenticate(url);

  /* const keys = await getApiKeys(); */
  const sessions = await getSessions();
  const $t = await getFormatter();
  const config = await getConfig();

  return {
    /* keys, */
    config,
    sessions,
    meta: {
      title: $t('settings'),
    },
  };
}) satisfies PageLoad;
