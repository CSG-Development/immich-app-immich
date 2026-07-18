<script lang="ts">
  import { shortcut } from '$lib/actions/shortcut';
  import { eventManager } from '$lib/managers/event-manager.svelte';
  import { handleError } from '$lib/utils/handle-error';
  import { updateAsset, type AssetResponseDto } from '@immich/sdk';
  import { Textarea, toastManager } from '@immich/ui';
  import { t } from 'svelte-i18n';
  import { fromAction } from 'svelte/attachments';
  import { untrack } from 'svelte';

  interface Props {
    asset: AssetResponseDto;
    isOwner: boolean;
  }

  let { asset, isOwner }: Props = $props();

  // Local draft. Re-sync only when navigating to a different asset — not when the
  // same asset is replaced (AssetUpdate / sidecar websocket), which was clearing the field.
  let description = $state(untrack(() => asset.exifInfo?.description ?? ''));
  let syncedAssetId = $state.raw(untrack(() => asset.id));

  $effect(() => {
    const nextId = asset.id;
    if (nextId === syncedAssetId) {
      return;
    }

    syncedAssetId = nextId;
    description = untrack(() => asset.exifInfo?.description ?? '');
  });

  const handleFocusOut = async () => {
    const currentDescription = untrack(() => asset.exifInfo?.description ?? '');
    if (description === currentDescription) {
      return;
    }

    const newDescription = description;
    try {
      const updated = await updateAsset({ id: asset.id, updateAssetDto: { description: newDescription } });
      description = newDescription;
      eventManager.emit('AssetUpdate', {
        ...updated,
        exifInfo: { ...updated.exifInfo, description: newDescription },
      });
      toastManager.primary($t('asset_description_updated'));
    } catch (error) {
      handleError(error, $t('cannot_update_the_description'));
    }
  };
</script>

{#if isOwner}
  <section class="px-3 py-3">
    <Textarea
      bind:value={description}
      class="max-h-[500px] w-full border-b border-gray-500 bg-transparent text-sm text-black outline-none transition-all focus:border-b-2 focus:border-immich-primary disabled:border-none dark:text-white dark:focus:border-immich-dark-primary immich-scrollbar placeholder:text-sm"
      rows={1}
      grow
      shape="rectangle"
      onfocusout={handleFocusOut}
      placeholder={$t('add_a_description')}
      data-testid="autogrow-textarea"
      {@attach fromAction(shortcut, () => ({
        shortcut: { key: 'Enter', ctrl: true },
        onShortcut: (e) => e.currentTarget.blur(),
      }))}
    />
  </section>
{:else if description}
  <section class="px-4 mt-6">
    <p class="break-words whitespace-pre-line w-full text-black dark:text-white text-sm">{description}</p>
  </section>
{/if}
