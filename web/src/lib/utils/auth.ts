import { browser } from '$app/environment';
import { resolveRoute } from '$app/paths';
import { purchaseStore } from '$lib/stores/purchase.store';
import { preferences as preferences$, user as user$ } from '$lib/stores/user.store';
import { userInteraction } from '$lib/stores/user.svelte';
import { getAboutInfo, getMyPreferences, getMyUser, getStorage } from '@immich/sdk';
import { redirect } from '@sveltejs/kit';
import { DateTime } from 'luxon';
import { get } from 'svelte/store';
import { AppRoute } from '../constants';

export interface AuthOptions {
  admin?: true;
  public?: true;
}

export const loadUser = async () => {
  try {
    let user = get(user$);
    let preferences = get(preferences$);
    let serverInfo;

    if ((!user || !preferences) && hasAuthCookie()) {
      [user, preferences, serverInfo] = await Promise.all([getMyUser(), getMyPreferences(), getAboutInfo()]);
      user$.set(user);
      preferences$.set(preferences);

      // Check for license status
      if (serverInfo.licensed || user.license?.activatedAt) {
        purchaseStore.setPurchaseStatus(true);
      }
    }
    return user;
  } catch {
    return null;
  }
};

const hasAuthCookie = (): boolean => {
  if (!browser) {
    return false;
  }

  for (const cookie of document.cookie.split('; ')) {
    const [name] = cookie.split('=');
    if (name === 'immich_is_authenticated') {
      return true;
    }
  }

  return false;
};

export const authenticate = async (url: URL, options?: AuthOptions) => {
  const { public: publicRoute, admin: adminRoute } = options || {};
  const user = await loadUser();

  if (publicRoute) {
    return;
  }

  if (!user) {
    redirect(302, resolveRoute(`${AppRoute.AUTH_LOGIN}?continue=${encodeURIComponent(url.pathname + url.search)}`, {}));
  }

  if (adminRoute && !user.isAdmin) {
    redirect(302, resolveRoute(AppRoute.PHOTOS, {}));
  }
};

export const requestServerInfo = async () => {
  if (get(user$)) {
    const data = await getStorage();
    userInteraction.serverInfo = data;
  }
};

export const getAccountAge = (): number => {
  const user = get(user$);

  if (!user) {
    return 0;
  }

  const createdDate = DateTime.fromISO(user.createdAt);
  const now = DateTime.now();
  const accountAge = now.diff(createdDate, 'days').days.toFixed(0);

  return Number(accountAge);
};
