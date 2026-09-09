<script lang="ts">
  import AlbumSharedLink from '$lib/components/album-page/album-shared-link.svelte';
  import HeaderActionButton from '$lib/components/HeaderActionButton.svelte';
  import OnEvents from '$lib/components/OnEvents.svelte';
  import UserAvatar from '$lib/components/shared-components/user-avatar.svelte';
  import {
    confirmLeaveAlbum,
    getAlbumActions,
    handleLeaveAlbum,
    handleRemoveUserFromAlbum,
    handleUpdateAlbum,
    handleUpdateUserAlbumRole,
  } from '$lib/services/album.service';
  import { user } from '$lib/stores/user.store';
  import { isAlbumEditor } from '$lib/utils/album-access';
  import {
    AlbumUserRole,
    AssetOrder,
    getAlbumInfo,
    getAllSharedLinks,
    type AlbumResponseDto,
    type SharedLinkResponseDto,
    type UserResponseDto,
  } from '@immich/sdk';
  import {
    Button,
    Field,
    HStack,
    Modal,
    ModalBody,
    ModalFooter,
    Select,
    Stack,
    Switch,
    Text,
    type SelectOption,
  } from '@immich/ui';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';

  type Props = {
    album: AlbumResponseDto;
    onClose: () => void;
  };

  let { album, onClose }: Props = $props();

  let closed = $state(false);
  const currentUserId = $derived($user.id);
  const isOwned = $derived(album.ownerId === currentUserId);
  const canEdit = $derived(isAlbumEditor(album, currentUserId));

  const closeModal = () => {
    if (closed) {
      return;
    }

    closed = true;
    onClose();
  };

  const getRoleOptions = (isCurrentUser: boolean) => {
    const options: SelectOption<AlbumUserRole | 'none'>[] = [
      { label: $t('role_editor'), value: AlbumUserRole.Editor },
      { label: $t('role_viewer'), value: AlbumUserRole.Viewer },
    ];

    if (canEdit && !isCurrentUser) {
      options.push({ label: $t('remove_user'), value: 'none' });
    }

    return options;
  };

  const handleRoleSelect = async (albumUser: UserResponseDto, role: AlbumUserRole | 'none') => {
    if (role === 'none') {
      await handleRemoveUserFromAlbum(album, albumUser);
      return;
    }

    await handleUpdateUserAlbumRole({ albumId: album.id, userId: albumUser.id, role });
  };

  const handleLeave = async () => {
    const confirmed = await confirmLeaveAlbum(album);
    if (!confirmed) {
      return;
    }

    closeModal();
    await handleLeaveAlbum(album);
  };

  const refreshAlbum = async () => {
    try {
      album = await getAlbumInfo({ id: album.id, withoutAssets: true });
    } catch {
      closeModal();
    }
  };

  const onAlbumUserDelete = async ({ userId }: { userId: string }) => {
    if (userId === currentUserId) {
      closeModal();
      return;
    }

    album.albumUsers = album.albumUsers.filter(({ user: { id } }) => id !== userId);
    await refreshAlbum();
  };

  const onSharedLinkCreate = (sharedLink: SharedLinkResponseDto) => {
    sharedLinks.push(sharedLink);
  };

  const onSharedLinkDelete = (sharedLink: SharedLinkResponseDto) => {
    sharedLinks = sharedLinks.filter(({ id }) => sharedLink.id !== id);
  };

  const { AddUsers, CreateSharedLink } = $derived(getAlbumActions($t, album));

  let sharedLinks: SharedLinkResponseDto[] = $state([]);

  onMount(async () => {
    try {
      sharedLinks = await getAllSharedLinks({ albumId: album.id });
    } catch {
      sharedLinks = [];
    }
  });
</script>

<OnEvents
  {onAlbumUserDelete}
  onAlbumShare={refreshAlbum}
  {onSharedLinkCreate}
  {onSharedLinkDelete}
  onAlbumUpdate={(newAlbum) => (album = newAlbum)}
/>

<Modal title={$t('options')} onClose={closeModal} size="small" class="overflow-visible!">
  <ModalBody class="overflow-visible!">
    <Stack gap={6} class="min-w-0" fullWidth>
      {#if canEdit}
        <div>
          <h2 class="text-xs mb-2 font-medium">{$t('settings').toUpperCase()}</h2>
          <div class="grid py-2 gap-y-2">
            {#if album.order}
              <Field label={$t('display_order')}>
                <Select
                  value={album.order}
                  options={[
                    { label: $t('newest_first'), value: AssetOrder.Desc },
                    { label: $t('oldest_first'), value: AssetOrder.Asc },
                  ]}
                  onChange={(value) => handleUpdateAlbum(album, { order: value })}
                />
              </Field>
            {/if}
            <Field label={$t('comments_and_likes')} description={$t('let_others_respond')}>
              <Switch
                checked={album.isActivityEnabled}
                onCheckedChange={(checked) => handleUpdateAlbum(album, { isActivityEnabled: checked })}
              />
            </Field>
          </div>
        </div>
      {/if}

      <div class="min-w-0">
        <HStack fullWidth class="justify-between mb-2">
          <Text size="medium" fontWeight="semi-bold">{$t('people')}</Text>
          <HeaderActionButton action={AddUsers} />
        </HStack>
        <div class="min-w-0 ps-2">
          <div class="mb-2 flex min-w-0 items-center gap-2">
            <div class="shrink-0">
              <UserAvatar user={album.owner} size="md" />
            </div>
            <Text class="min-w-0 flex-1 truncate" size="small" title={album.owner.name}>{album.owner.name}</Text>
            <Field disabled class="w-32 shrink-0">
              <Select options={[{ label: $t('owner'), value: 'owner' }]} value="owner" />
            </Field>
          </div>

          {#each album.albumUsers as { user: albumUser, role } (albumUser.id)}
            {@const isCurrentUser = albumUser.id === currentUserId}
            <div class="flex min-w-0 items-center gap-4 py-2">
              <div class="flex min-w-0 flex-1 items-center gap-2">
                <div class="shrink-0">
                  <UserAvatar user={albumUser} size="md" />
                </div>
                <Text class="min-w-0 flex-1 truncate" size="small" title={albumUser.name}>{albumUser.name}</Text>
              </div>
              <Field class="w-32 shrink-0" disabled={!canEdit}>
                <Select
                  value={role}
                  options={getRoleOptions(isCurrentUser)}
                  onChange={(value) => handleRoleSelect(albumUser, value)}
                />
              </Field>
            </div>
          {/each}
        </div>
      </div>
      {#if canEdit || sharedLinks.length > 0}
        <div class="mb-4">
          <HStack class="justify-between mb-2">
            <Text size="medium" fontWeight="semi-bold">{$t('shared_links')}</Text>
            <HeaderActionButton action={CreateSharedLink} />
          </HStack>

          <div class="ps-2">
            <Stack gap={4}>
              {#each sharedLinks as sharedLink (sharedLink.id)}
                <AlbumSharedLink {album} {sharedLink} canManage={canEdit} />
              {/each}
            </Stack>
          </div>
        </div>
      {/if}
    </Stack>
  </ModalBody>
  {#if !isOwned}
    <ModalFooter>
      <Button
        shape="round"
        color="danger"
        size="standard-large"
        class="font-normal"
        fullWidth
        onclick={() => void handleLeave()}
      >
        {$t('leave_album')}
      </Button>
    </ModalFooter>
  {/if}
</Modal>
