import { OpenQueryParam } from '$lib/constants';
import { Route } from '$lib/route';

describe('Route', () => {
  describe(Route.login.name, () => {
    it('should encode continue', () => {
      expect(Route.login({ continue: '/some/path?with=query', autoLaunch: 1 })).toBe(
        '/photos/auth/login?continue=%2Fsome%2Fpath%3Fwith%3Dquery&autoLaunch=1',
      );
    });
  });

  describe(Route.search.name, () => {
    it('should work', () => {
      expect(Route.search({})).toBe('/photos/search');
    });

    it('should work', () => {
      expect(Route.search({ make: undefined, model: 'Immich' })).toBe(
        '/photos/search?query=%7B%22model%22%3A%22Immich%22%7D',
      );
    });

    it('should support query parameters', () => {
      expect(Route.systemSettings({ isOpen: OpenQueryParam.OAUTH })).toBe(
        '/photos/admin/system-settings?isOpen=oauth',
      );
    });
  });

  describe(Route.tags.name, () => {
    it('should work', () => {
      expect(Route.tags()).toBe('/photos/tags');
    });

    it('should support query parameters', () => {
      expect(Route.tags({ path: '/some/path' })).toBe('/photos/tags?path=%2Fsome%2Fpath');
    });

    it('should ignore an empty path', () => {
      expect(Route.tags({ path: '' })).toBe('/photos/tags');
    });
  });

  describe(Route.systemSettings.name, () => {
    it('should work', () => {
      expect(Route.systemSettings()).toBe('/photos/admin/system-settings');
    });

    it('should support query parameters', () => {
      expect(Route.systemSettings({ isOpen: OpenQueryParam.OAUTH })).toBe(
        '/photos/admin/system-settings?isOpen=oauth',
      );
    });
  });
});
