<script lang="ts">
  import { shortcut } from '$lib/actions/shortcut';
  import { eventManager } from '$lib/managers/event-manager.svelte';
  import { handleError } from '$lib/utils/handle-error';
  import { updateAlbumInfo } from '@immich/sdk';
  import { Textarea } from '@immich/ui';
  import { t } from 'svelte-i18n';
  import { fromAction } from 'svelte/attachments';
  import { tick } from 'svelte';

  type Props = {
    id: string;
    albumName: string;
    isOwned: boolean;
    onUpdate: (albumName: string) => void;
  };

  let { id, albumName = $bindable(), isOwned, onUpdate }: Props = $props();

  let newAlbumName = $state(albumName);
  let textareaRef = $state<HTMLTextAreaElement | null>(null);

  const MAX_LINES = 2;

  const syncTextareaHeight = (element: HTMLTextAreaElement) => {
    const style = getComputedStyle(element);
    let lineHeight = Number.parseFloat(style.lineHeight);

    element.style.height = 'auto';

    if (!Number.isFinite(lineHeight)) {
      lineHeight = element.scrollHeight;
    }

    const maxHeight = lineHeight * MAX_LINES;
    const scrollHeight = element.scrollHeight;

    if (scrollHeight > maxHeight) {
      element.style.height = `${maxHeight}px`;
      element.style.overflowY = 'auto';
    } else {
      element.style.height = `${scrollHeight}px`;
      element.style.overflowY = 'hidden';
    }
  };

  $effect(() => {
    newAlbumName = albumName;
  });

  $effect(() => {
    const element = textareaRef;
    void newAlbumName;
    if (!element) {
      return;
    }

    void tick().then(() => {
      if (textareaRef !== element) {
        return;
      }
      syncTextareaHeight(element);
    });

    const onResize = () => syncTextareaHeight(element);
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  });

  const handleUpdate = async () => {
    newAlbumName = newAlbumName.replaceAll('\n', ' ').trim();

    if (newAlbumName === albumName) {
      return;
    }

    try {
      const response = await updateAlbumInfo({ id, updateAlbumDto: { albumName: newAlbumName } });
      ({ albumName } = response);
      eventManager.emit('AlbumUpdate', response);
      onUpdate(albumName);
    } catch (error) {
      handleError(error, $t('errors.unable_to_save_album'));
    }
  };

  const textClasses = 'text-2xl lg:text-6xl text-primary';
</script>

<div class="mb-2">
  {#if isOwned}
    <Textarea
      bind:ref={textareaRef}
      bind:value={newAlbumName}
      shape="rectangle"
      rows={1}
      title={$t('edit_title')}
      onblur={handleUpdate}
      oninput={(event) => syncTextareaHeight(event.currentTarget as HTMLTextAreaElement)}
      placeholder={$t('add_a_title')}
      class="{textClasses} immich-scrollbar w-[99%] border-none bg-transparent px-0 py-0 outline-none transition-all hover:border-b-2 hover:border-gray-400 focus:border-none placeholder:text-primary/90"
      {@attach fromAction(shortcut, () => ({
        shortcut: { key: 'Enter' },
        onShortcut: (event) => event.currentTarget.blur(),
      }))}
    />
  {:else}
    <div class={textClasses}>{newAlbumName}</div>
  {/if}
</div>
