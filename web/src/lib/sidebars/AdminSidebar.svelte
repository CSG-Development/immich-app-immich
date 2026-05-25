<script lang="ts">
  import { resolve } from '$app/paths';
  import BottomInfo from '$lib/components/shared-components/side-bar/bottom-info.svelte';
  import { AppRoute } from '$lib/constants';
  import { NavbarItem } from '@immich/ui';
  import { mdiAccountMultipleOutline, mdiBookshelf, mdiCog, mdiServer, mdiSync } from '@mdi/js';
  import { t } from 'svelte-i18n';
</script>

<div class="h-full flex flex-col justify-between gap-2">
  <div class="flex flex-col pt-8 pe-4 gap-1">
    <NavbarItem title={$t('users')} href={resolve(AppRoute.ADMIN_USER_MANAGEMENT)} icon={mdiAccountMultipleOutline} />
    <NavbarItem title={$t('jobs')} href={resolve(AppRoute.ADMIN_JOBS)} icon={mdiSync} />
    <NavbarItem title={$t('settings')} href={resolve(AppRoute.ADMIN_SETTINGS)} icon={mdiCog} />
    <NavbarItem
      title={$t('external_libraries')}
      href={resolve(AppRoute.ADMIN_LIBRARY_MANAGEMENT)}
      icon={mdiBookshelf}
    />
    <NavbarItem title={$t('server_stats')} href={resolve(AppRoute.ADMIN_STATS)} icon={mdiServer} />
  </div>

  <div class="mb-2 me-4">
    <BottomInfo />
  </div>
</div>
