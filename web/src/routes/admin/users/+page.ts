/* eslint-disable unicorn/no-empty-file */
/* import { authenticate, requestServerInfo } from '$lib/utils/auth';
import { getFormatter } from '$lib/utils/i18n';
import { searchUsersAdmin } from '@immich/sdk';
import type { PageLoad } from './$types';

export const load = (async ({ url }) => {
  await authenticate(url, { admin: true });
  await requestServerInfo();
  const allUsers = await searchUsersAdmin({ withDeleted: true });
  const $t = await getFormatter();

  return {
    allUsers,
    meta: {
      title: $t('admin.user_management'),
    },
  };
}) satisfies PageLoad;
 */
