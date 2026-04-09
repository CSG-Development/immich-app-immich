<script lang="ts">
  import { resolve } from '$app/paths';
  import AlbumSharedLink from '$lib/components/album-page/album-shared-link.svelte';
  import { AppRoute } from '$lib/constants';
  import Dropdown from '$lib/elements/Dropdown.svelte';
  import QrCodeModal from '$lib/modals/QrCodeModal.svelte';
  import { makeSharedLinkUrl } from '$lib/utils';
  import {
    AlbumUserRole,
    getAllSharedLinks,
    searchUsers,
    type AlbumResponseDto,
    type AlbumUserAddDto,
    type SharedLinkResponseDto,
    type UserResponseDto,
  } from '@immich/sdk';
  import { Button, Icon, Link, Modal, ModalBody, modalManager, Stack, Text } from '@immich/ui';
  import { mdiCheck, mdiEye, mdiLink, mdiPencil } from '@mdi/js';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import UserAvatar from '../components/shared-components/user-avatar.svelte';

  interface Props {
    album: AlbumResponseDto;
    onClose: (result?: { action: 'sharedLink' } | { action: 'sharedUsers'; data: AlbumUserAddDto[] }) => void;
  }

  let { album, onClose }: Props = $props();

  let users: UserResponseDto[] = $state([]);
  let selectedUsers: Record<string, { user: UserResponseDto; role: AlbumUserRole }> = $state({});
  let dropdownOpen = $state(false);

  const handleViewQrCode = async (sharedLink: SharedLinkResponseDto) => {
    await modalManager.show(QrCodeModal, {
      title: $t('view_link'),
      value: makeSharedLinkUrl(sharedLink),
      mdFullSize: false,
    });
  };

  const roleOptions: Array<{ title: string; value: AlbumUserRole | 'none'; icon?: string }> = [
    { title: $t('role_editor'), value: AlbumUserRole.Editor, icon: mdiPencil },
    { title: $t('role_viewer'), value: AlbumUserRole.Viewer, icon: mdiEye },
    { title: $t('remove_user'), value: 'none' },
  ];

  let sharedLinks: SharedLinkResponseDto[] = $state([]);
  onMount(async () => {
    sharedLinks = await getAllSharedLinks({ albumId: album.id });
    const data = await searchUsers();

    // remove album owner
    users = data.filter((user) => user.id !== album.ownerId);

    // Remove the existed shared users from the album
    for (const sharedUser of album.albumUsers) {
      users = users.filter((user) => user.id !== sharedUser.user.id);
    }
  });

  const handleToggle = (user: UserResponseDto) => {
    if (Object.keys(selectedUsers).includes(user.id)) {
      delete selectedUsers[user.id];
    } else {
      selectedUsers[user.id] = { user, role: AlbumUserRole.Editor };
    }
  };

  const handleChangeRole = (user: UserResponseDto, role: AlbumUserRole | 'none') => {
    if (role === 'none') {
      delete selectedUsers[user.id];
    } else {
      selectedUsers[user.id].role = role;
    }
  };

  const disableScroll = (event: Event) => {
    event.preventDefault();
    event.stopPropagation();
    return false;
  };

  const disableScrollWithButtons = (event: Event) => {
    if (
      ['Space', 'ArrowUp', 'ArrowDown', 'ArrowLeft', 'ArrowRight', 'PageUp', 'PageDown', 'Home', 'End'].includes(
        (event as KeyboardEvent).code,
      )
    ) {
      event.preventDefault();
    }
  };

  $effect(() => {
    const div = document.querySelector('#container');
    if (dropdownOpen) {
      div?.addEventListener('scroll', disableScroll, false);
      div?.addEventListener('mousewheel', disableScroll, false);
      div?.addEventListener('touchmove', disableScroll, false);
      div?.addEventListener('keydown', disableScrollWithButtons, false);
    } else {
      div?.removeEventListener('scroll', disableScroll, false);
      div?.removeEventListener('mousewheel', disableScroll, false);
      div?.removeEventListener('touchmove', disableScroll, false);
      div?.removeEventListener('keydown', disableScrollWithButtons, false);
    }
  });
</script>

<Modal size="small" title={$t('share')} {onClose} class="overflow-visible">
  <ModalBody>
    {#if Object.keys(selectedUsers).length > 0}
      <div class="mb-2 py-2">
        <p class="text-xs font-medium">{$t('selected')}</p>
        <div id="container" class="my-2 max-h-[200px] overflow-y-auto">
          {#each Object.values(selectedUsers) as { user } (user.id)}
            {#key user.id}
              <div class="flex place-items-center gap-4 p-4">
                <div
                  class="flex h-10 w-10 items-center justify-center rounded-full border bg-green-600 text-3xl text-white"
                >
                  <Icon icon={mdiCheck} size="24" />
                </div>

                <!-- <UserAvatar {user} size="md" /> -->
                <div class="text-start grow max-w-[152px]">
                  <p class="text-immich-fg dark:text-immich-dark-fg truncate">
                    {user.name}
                  </p>
                  <p class="text-xs truncate">
                    {user.email}
                  </p>
                </div>

                <Dropdown
                  title={$t('role')}
                  options={roleOptions}
                  render={({ title, icon }) => ({ title, icon })}
                  onSelect={({ value }) => handleChangeRole(user, value)}
                  onShowMenuChange={(show) => (dropdownOpen = show)}
                  position="bottom-right"
                  class="!min-w-[240px]"
                  isShareModal
                />
              </div>
            {/key}
          {/each}
        </div>
      </div>
    {/if}

    {#if users.length + Object.keys(selectedUsers).length === 0}
      <p class="p-5 text-sm">
        {$t('album_share_no_users')}
      </p>
    {/if}

    <div class="immich-scrollbar">
      {#if users.length > 0 && users.length !== Object.keys(selectedUsers).length}
        <Text>{$t('users')}</Text>

        <div class="my-2 max-h-[200px] overflow-y-auto">
          {#each users as user (user.id)}
            {#if !Object.keys(selectedUsers).includes(user.id)}
              <div class="flex place-items-center transition-all hover:bg-gray-200 dark:hover:bg-gray-700 rounded-xl">
                <button
                  type="button"
                  onclick={() => handleToggle(user)}
                  class="flex w-full place-items-center gap-4 p-4"
                >
                  <UserAvatar {user} size="md" />
                  <div class="text-start grow max-w-[152px]">
                    <p class="text-immich-fg dark:text-immich-dark-fg truncate">
                      {user.name}
                    </p>
                    <p class="text-xs truncate">
                      {user.email}
                    </p>
                  </div>
                </button>
              </div>
            {/if}
          {/each}
        </div>
      {/if}
    </div>

    {#if users.length > 0}
      <div class="py-3">
        <Button
          size="small"
          fullWidth
          shape="round"
          variant="outline"
          disabled={Object.keys(selectedUsers).length === 0}
          onclick={() =>
            onClose({
              action: 'sharedUsers',
              data: Object.values(selectedUsers).map(({ user, ...rest }) => ({ userId: user.id, ...rest })),
            })}
          class="bg-transparent"
        >
          {$t('add')}
        </Button>
      </div>
    {/if}

    <hr class="my-4" />

    <Stack gap={6}>
      {#if sharedLinks.length > 0}
        <div class="flex justify-between items-center">
          <Text>{$t('shared_links')}</Text>
          <Link href={resolve(AppRoute.SHARED_LINKS)} onclick={() => onClose()} class="text-sm">{$t('view_all')}</Link>
        </div>

        <div class="max-h-[40px] overflow-y-auto">
          <Stack gap={4}>
            {#each sharedLinks as sharedLink (sharedLink.id)}
              <AlbumSharedLink {album} {sharedLink} onViewQrCode={() => handleViewQrCode(sharedLink)} />
            {/each}
          </Stack>
        </div>
      {/if}

      <Button
        leadingIcon={mdiLink}
        size="small"
        shape="round"
        fullWidth
        onclick={() => onClose({ action: 'sharedLink' })}>{$t('create_link')}</Button
      >
    </Stack>
  </ModalBody>
</Modal>
