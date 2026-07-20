import { OpenQueryParam, type SharedLinkTab } from '$lib/constants';
import { getBaseUrl, QueueName, type MetadataSearchDto, type SmartSearchDto } from '@immich/sdk';
import { omitBy } from 'lodash-es';

const asQueueSlug = (name: QueueName) => {
  return name.replaceAll(/[A-Z]/g, (m) => '-' + m.toLowerCase());
};

export const fromQueueSlug = (slug: string): QueueName | undefined => {
  const name = slug.replaceAll(/-([a-z])/g, (_, c) => c.toUpperCase());
  if (Object.values(QueueName).includes(name as QueueName)) {
    return name as QueueName;
  }
};

type QueryValue = number | string;
const asQueryString = (
  params?: Record<string, QueryValue | undefined>,
  options?: { skipEmptyStrings?: boolean; skipNullValues?: boolean },
) => {
  const { skipEmptyStrings = true, skipNullValues = true } = options ?? {};
  const items = Object.entries(params ?? {})
    .filter((item): item is [string, QueryValue] => {
      const value = item[1];

      if (value === undefined) {
        return false;
      }

      if (skipNullValues && value === null) {
        return false;
      }

      if (skipEmptyStrings && value === '') {
        return false;
      }

      return true;
    })
    .map(([key, value]) => `${encodeURIComponent(key)}=${encodeURIComponent(value)}`);

  return items.length === 0 ? '' : `?${items.join('&')}`;
};

const DOCS_BASE = 'https://docs.immich.app';
const base = '/photos';

export const Docs = {
  duplicates: () => `${DOCS_BASE}/features/duplicates-utility`,
};

export const Route = {
  // auth
  login: (params?: { continue?: string; autoLaunch?: 0 | 1 }) => `${base}/auth/login` + asQueryString(params),
  logout: (params?: { continue?: string }) => `${base}/auth/logout` + asQueryString(params),
  register: () => `${base}/auth/register`,
  changePassword: () => `${base}/auth/change-password`,
  onboarding: (params?: { step?: string }) => `${base}/auth/onboarding` + asQueryString(params),
  pinPrompt: (params?: { continue?: string }) =>
    `${base}/auth/pin-prompt` + asQueryString({ continue: params?.continue }),

  // albums
  albums: () => `${base}/albums`,
  viewAlbum: ({ id }: { id: string }) => `${base}/albums/${id}`,
  viewAlbumAsset: ({ albumId, assetId }: { albumId: string; assetId: string }) =>
    `${base}/albums/${albumId}/photos/${assetId}`,

  // buy
  buy: () => `${base}/buy`,

  // explore
  explore: () => `${base}/explore`,
  places: () => `${base}/places`,

  // folders
  folders: (params?: { path?: string }) => `${base}/folders` + asQueryString(params),

  // libraries
  libraries: () => `${base}/admin/library-management`,
  newLibrary: () => `${base}/admin/library-management/new`,
  viewLibrary: ({ id }: { id: string }) => `${base}/admin/library-management/${id}`,
  editLibrary: ({ id }: { id: string }) => `${base}/admin/library-management/${id}/edit`,

  // maintenance
  maintenanceMode: (params?: { continue?: string }) => `${base}/maintenance` + asQueryString(params),

  // map
  map: (point?: { zoom: number; lat: number; lng: number }) =>
    `${base}/map` + (point ? `#${point.zoom}/${point.lat}/${point.lng}` : ''),

  // memories
  memories: (params?: { id?: string }) => `${base}/memory` + asQueryString(params),

  // partners
  viewPartner: ({ id }: { id: string }) => `${base}/partners/${id}`,

  // people
  people: () => `${base}/people`,
  viewPerson: ({ id }: { id: string }, params?: { previousRoute?: string; action?: 'merge' }) =>
    `${base}/people/${id}` + asQueryString(params),

  // photos
  photos: (params?: { at?: string }) => `${base}/photos` + asQueryString(params),
  viewAsset: ({ id }: { id: string }) => `${base}/photos/${id}`,
  archive: () => `${base}/archive`,
  favorites: () => `${base}/favorites`,
  locked: () => `${base}/locked`,
  trash: () => `${base}/trash`,
  viewTrashedAsset: ({ id }: { id: string }) => `${base}/trash/photos/${id}`,

  // search
  search: (dto?: MetadataSearchDto | SmartSearchDto) => {
    const metadata = omitBy(dto ?? {}, (value) => value === undefined);
    const query = Object.keys(metadata).length === 0 ? undefined : JSON.stringify(metadata);
    return `${base}/search` + asQueryString({ query });
  },

  // sharing
  sharing: () => `${base}/sharing`,

  // shared links
  sharedLinks: (params?: { filter?: SharedLinkTab }) => `${base}/shared-links` + asQueryString(params),
  editSharedLink: ({ id }: { id: string }) => `${base}/shared-links/${id}/edit`,
  viewSharedLink: ({ slug, key }: { slug?: string | null; key: string }) =>
    slug ? `${base}/s/${slug}` : `${base}/share/${key}`,

  // settings
  userSettings: (params?: { isOpen?: OpenQueryParam }) => `${base}/user-settings` + asQueryString(params),

  // system
  systemSettings: (params?: { isOpen?: OpenQueryParam }) => `${base}/admin/system-settings` + asQueryString(params),
  systemStatistics: () => `${base}/admin/server-status`,
  systemMaintenance: (params?: { continue?: string }) => `${base}/admin/maintenance` + asQueryString(params),

  // tags
  tags: (params?: { path?: string }) => `${base}/tags` + asQueryString(params),

  // users
  users: () => `${base}/admin/users`,
  newUser: () => `${base}/admin/users/new`,
  viewUser: ({ id }: { id: string }) => `${base}/admin/users/${id}`,
  editUser: ({ id }: { id: string }) => `${base}/admin/users/${id}/edit`,

  // utilities
  utilities: () => `${base}/utilities`,
  duplicatesUtility: (params?: { index?: number }) => `${base}/utilities/duplicates` + asQueryString(params),
  largeFileUtility: () => `${base}/utilities/large-files`,
  geolocationUtility: () => `${base}/utilities/geolocation`,

  // workflows
  workflows: () => `${base}/utilities/workflows`,
  viewWorkflow: ({ id }: { id: string }) => `${base}/utilities/workflows/${id}`,

  // queues
  queues: () => `${base}/admin/queues`,
  viewQueue: ({ name }: { name: QueueName }) => `${base}/admin/queues/${asQueueSlug(name)}`,

  // editor
  editor: (params?: { assetId?: string }) => `${base}/editor` + asQueryString(params),

  // integrity checks
  integrityReportFile: (reportId: string) => `${getBaseUrl()}/admin/integrity/report/${reportId}/file`,

  // continue helper for ensuring same-origin URLs
  continue: (url: string | null, fallback: string): string | URL => {
    const resolved = new URL(url ?? fallback, globalThis.location.href);

    if (resolved.origin !== globalThis.location.origin) {
      return fallback;
    }

    return resolved;
  },
};
