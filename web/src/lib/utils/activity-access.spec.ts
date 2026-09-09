import { activityAlreadyDeletedMessageKey, isActivityNotFoundError } from '$lib/utils/activity-access';
import { ReactionType } from '@immich/sdk';

vi.mock('$lib/utils/handle-error', () => ({
  getServerErrorMessage: (error: unknown) => {
    if (error && typeof error === 'object' && 'data' in error) {
      return (error as { data?: { message?: string } }).data?.message;
    }
    return undefined;
  },
}));

describe('activity-access utils', () => {
  describe('isActivityNotFoundError', () => {
    it('detects deleted or inaccessible activity', () => {
      expect(isActivityNotFoundError({ data: { message: 'Not found or no activity.delete access' } })).toBe(true);
    });

    it('ignores unrelated errors', () => {
      expect(isActivityNotFoundError({ data: { message: 'Not found or no album.read access' } })).toBe(false);
      expect(isActivityNotFoundError({ data: { message: 'Something else' } })).toBe(false);
      expect(isActivityNotFoundError({})).toBe(false);
    });
  });

  describe('activityAlreadyDeletedMessageKey', () => {
    it('maps reaction types to i18n keys', () => {
      expect(activityAlreadyDeletedMessageKey(ReactionType.Comment)).toBe('errors.comment_already_deleted');
      expect(activityAlreadyDeletedMessageKey(ReactionType.Like)).toBe('errors.like_already_deleted');
    });
  });
});
