import { getServerErrorMessage } from '$lib/utils/handle-error';
import { ReactionType } from '@immich/sdk';

export const isActivityNotFoundError = (error: unknown): boolean => {
  const message = getServerErrorMessage(error) ?? '';
  return /not found or no activity\.delete access/i.test(message);
};

export const activityAlreadyDeletedMessageKey = (
  type: ReactionType,
): 'errors.comment_already_deleted' | 'errors.like_already_deleted' =>
  type === ReactionType.Comment ? 'errors.comment_already_deleted' : 'errors.like_already_deleted';
