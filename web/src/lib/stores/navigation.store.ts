import { persisted } from 'svelte-persisted-store';

/* export const previousRoute = writable<string | null>(null); */
export const albumPreviousRoute = persisted<string | null>('album-previous-route', null);
