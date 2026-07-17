import { handleError } from '$lib/utils/handle-error';
import { getFormatter } from '$lib/utils/i18n';
import { emptyTrash, restoreTrash } from '@immich/sdk';
import { modalManager, toastManager, type ActionItem } from '@immich/ui';
import { mdiDeleteForeverOutline, mdiHistory } from '@mdi/js';
import type { MessageFormatter } from 'svelte-i18n';

type OnTrashCleared = () => void | Promise<void>;

export const getTrashActions = ($t: MessageFormatter, onTrashCleared?: OnTrashCleared) => {
  const RestoreAll: ActionItem = {
    title: $t('restore_all'),
    icon: mdiHistory,
    onAction: () => handleRestoreTrash(onTrashCleared),
  };

  const Empty: ActionItem = {
    title: $t('empty_trash'),
    icon: mdiDeleteForeverOutline,
    onAction: () => handleEmptyTrash(onTrashCleared),
  };

  return { RestoreAll, Empty };
};

export const handleEmptyTrash = async (onTrashCleared?: OnTrashCleared) => {
  const $t = await getFormatter();

  const confirmed = await modalManager.showDialog({ prompt: $t('empty_trash_confirmation') });
  if (!confirmed) {
    return;
  }

  try {
    const { count } = await emptyTrash();
    await onTrashCleared?.();
    toastManager.primary($t('assets_permanently_deleted_count', { values: { count } }));
  } catch (error) {
    handleError(error, $t('errors.unable_to_empty_trash'));
  }
};

export const handleRestoreTrash = async (onTrashCleared?: OnTrashCleared) => {
  const $t = await getFormatter();

  const confirmed = await modalManager.showDialog({ prompt: $t('assets_restore_confirmation') });
  if (!confirmed) {
    return;
  }

  try {
    const { count } = await restoreTrash();
    await onTrashCleared?.();
    toastManager.primary($t('assets_restored_count', { values: { count } }));
  } catch (error) {
    handleError(error, $t('errors.unable_to_restore_trash'));
  }
};
