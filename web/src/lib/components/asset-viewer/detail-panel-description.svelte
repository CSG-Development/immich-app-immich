<script lang="ts">
  import { shortcut } from '$lib/actions/shortcut';
  import { eventManager } from '$lib/managers/event-manager.svelte';
  import { handleError } from '$lib/utils/handle-error';
  import { updateAsset, getAssetInfo, type AssetResponseDto } from '@immich/sdk';
  import { Textarea, toastManager } from '@immich/ui';
  import { t } from 'svelte-i18n';
  import { fromAction } from 'svelte/attachments';
  import { tick, untrack } from 'svelte';

  interface Props {
    asset: AssetResponseDto;
    isOwner: boolean;
  }

  let { asset, isOwner }: Props = $props();

  // Local draft. Re-sync only when navigating to a different asset — not when the
  // same asset is replaced (AssetUpdate / sidecar websocket), which was clearing the field.
  let description = $state(untrack(() => asset.exifInfo?.description ?? ''));
  let syncedAssetId = $state.raw(untrack(() => asset.id));
  let textareaRef = $state<HTMLTextAreaElement | null>(null);

  $effect(() => {
    const nextId = asset.id;
    if (nextId === syncedAssetId) {
      return;
    }

    syncedAssetId = nextId;
    description = untrack(() => asset.exifInfo?.description ?? '');
  });

  // Textarea `grow` only resizes on input; re-apply after load/navigation so long
  // descriptions aren't clipped after a page refresh.
  $effect(() => {
    const element = textareaRef;
    void description;
    if (!element) {
      return;
    }

    void tick().then(() => {
      if (textareaRef !== element) {
        return;
      }
      element.style.height = 'auto';
      element.style.height = `${element.scrollHeight}px`;
    });
  });

  const handleFocusOut = async () => {
    const currentDescription = untrack(() => asset.exifInfo?.description ?? '');
    if (description === currentDescription) {
      return;
    }

    const newDescription = description;
    try {
      await updateAsset({ id: asset.id, updateAssetDto: { description: newDescription } });
      // Refresh from server so Metadata (and other panels) get the persisted exifInfo.
      const refreshed = await getAssetInfo({ id: asset.id });
      description = refreshed.exifInfo?.description ?? newDescription;
      eventManager.emit('AssetUpdate', {
        ...refreshed,
        exifInfo: { ...refreshed.exifInfo, description: refreshed.exifInfo?.description ?? newDescription },
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
      bind:ref={textareaRef}
      bind:value={description}
      class="max-h-[500px] w-full break-words border-b border-gray-500 bg-transparent text-sm text-black outline-none transition-all focus:border-b-2 focus:border-immich-primary disabled:border-none dark:text-white dark:focus:border-immich-dark-primary immich-scrollbar placeholder:text-sm"
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
