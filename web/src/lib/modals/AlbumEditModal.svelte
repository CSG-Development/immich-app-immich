<script lang="ts">
  import AlbumCover from '$lib/components/album-page/album-cover.svelte';
  import { handleUpdateAlbum } from '$lib/services/album.service';
  import { resolveAlbumName } from '$lib/utils/album-name';
  import { type AlbumResponseDto } from '@immich/sdk';
  import { Field, FormModal, Input, Textarea } from '@immich/ui';
  import { mdiRenameOutline } from '@mdi/js';
  import { t } from 'svelte-i18n';

  type Props = {
    album: AlbumResponseDto;
    onClose: () => void;
  };

  let { album, onClose }: Props = $props();

  let albumName = $state(album.albumName);
  let description = $state(album.description);

  const onSubmit = async () => {
    const success = await handleUpdateAlbum(album, {
      albumName: resolveAlbumName(albumName),
      description,
    });
    if (success) {
      onClose();
    }
  };
</script>

<FormModal icon={mdiRenameOutline} title={$t('edit_album')} size="medium" {onClose} {onSubmit}>
  <div class="flex flex-col md:flex-row items-center gap-6 md:m-4">
    <AlbumCover {album} class="h-[212px] w-[212px] shadow-lg sm:flex mr-auto md:mr-0 rounded-3xl!" />

    <div class="grow flex flex-col gap-4 w-full md:w-auto">
      <Field label={$t('name')}>
        <Input bind:value={albumName} />
      </Field>

      <Field label={$t('description')}>
        <Textarea bind:value={description} />
      </Field>
    </div>
  </div>
</FormModal>
