import { browser } from '$app/environment';

import { eventManager } from '$lib/managers/event-manager.svelte';
import { PersistedLocalStorage } from '$lib/utils/persisted';
import { Theme } from '@immich/ui';

export interface ThemeSetting {
  value: Theme;
}

const getDefaultTheme = () => {
  if (!browser) {
    return Theme.Dark;
  }

  return globalThis.matchMedia('(prefers-color-scheme: dark)').matches ? Theme.Dark : Theme.Light;
};

class ThemeManager {
  #theme = new PersistedLocalStorage<ThemeSetting>(
    'immich-ui-theme',
    { value: getDefaultTheme() },
    {
      valid: (value): value is ThemeSetting => {
        return Object.values(Theme).includes((value as ThemeSetting)?.value);
      },
    },
  );

  get theme() {
    return this.#theme.current;
  }

  value = $derived(this.theme.value);

  isDark = $derived(this.value === Theme.Dark);

  setSystem() {
    this.#update(getDefaultTheme());
  }

  setTheme(theme: Theme) {
    this.#update(theme);
  }

  toggleTheme() {
    this.#update(this.value === Theme.Dark ? Theme.Light : Theme.Dark);
  }

  #update(value: Theme) {
    const theme: ThemeSetting = { value };

    if (theme.value === Theme.Light) {
      document.documentElement.classList.remove('dark');
    } else {
      document.documentElement.classList.add('dark');
    }

    this.#theme.current = theme;

    eventManager.emit('theme.change', theme);
  }
}

export const themeManager = new ThemeManager();
