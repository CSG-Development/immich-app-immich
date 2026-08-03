import { systemConfigManager } from '$lib/managers/system-config-manager.svelte';
import { user } from '$lib/stores/user.store';
import { authenticate } from '$lib/utils/auth';
import { getFormatter } from '$lib/utils/i18n';
import { getApiKeys, getSessions } from '@immich/sdk';
import { get } from 'svelte/store';
import type { PageLoad } from './$types';

export const load = (async ({ url }) => {
  await authenticate(url);

  const keys = await getApiKeys();
  const sessions = await getSessions();
  const $t = await getFormatter();

  if (get(user).isAdmin) {
    await systemConfigManager.init();
  }

  return {
    keys,
    sessions,
    meta: {
      title: $t('settings'),
    },
  };
}) satisfies PageLoad;
