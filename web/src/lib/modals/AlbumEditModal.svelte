<script lang="ts">
  import AlbumCover from '$lib/components/album-page/album-cover.svelte';
  import { handleError } from '$lib/utils/handle-error';
  import { updateAlbumInfo, type AlbumResponseDto } from '@immich/sdk';
  import { Button, Field, HStack, Input, Modal, ModalBody, ModalFooter, Textarea } from '@immich/ui';
  import { mdiPencilOutline } from '@mdi/js';
  import { t } from 'svelte-i18n';

  type Props = {
    album: AlbumResponseDto;
    onClose: (album?: AlbumResponseDto) => void;
  };

  let { album = $bindable(), onClose }: Props = $props();

  let albumName = $state(album.albumName);
  let description = $state(album.description);
  let isSubmitting = $state(false);

  const handleSubmit = async (event: Event) => {
    event.preventDefault();

    isSubmitting = true;

    try {
      await updateAlbumInfo({ id: album.id, updateAlbumDto: { albumName, description } });
      album.albumName = albumName;
      album.description = description;
      onClose(album);
    } catch (error) {
      handleError(error, $t('errors.unable_to_update_album_info'));
    } finally {
      isSubmitting = false;
    }
  };
</script>

<Modal icon={mdiPencilOutline} title={$t('edit_album')} size="medium" {onClose}>
  <ModalBody>
    <form onsubmit={handleSubmit} autocomplete="off" id="edit-album-form">
      <div class="flex flex-col md:flex-row items-center gap-6 md:m-4">
        <AlbumCover {album} class="h-[212px] w-[212px] shadow-lg sm:flex mr-auto md:mr-0 rounded-3xl!" />

        <div class="grow flex flex-col gap-4 w-full md:w-auto">
          <Field label={$t('name')}>
            <Input bind:value={albumName} />
          </Field>

          <Field label={$t('description')}>
            <Textarea bind:value={description} class="h-22 rounded-3xl" />
          </Field>
        </div>
      </div>
    </form>
  </ModalBody>

  <ModalFooter>
    <HStack fullWidth>
      <Button
        shape="round"
        color="secondary"
        size="standard-large"
        class="font-normal"
        fullWidth
        onclick={() => onClose()}>{$t('cancel')}</Button
      >
      <Button
        shape="round"
        type="submit"
        size="standard-large"
        class="font-normal"
        fullWidth
        disabled={isSubmitting}
        form="edit-album-form">{$t('save')}</Button
      >
    </HStack>
  </ModalFooter>
</Modal>
