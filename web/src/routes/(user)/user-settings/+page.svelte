<script lang="ts">
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import UserSettingsList from '$lib/components/user-settings-page/user-settings-list.svelte';
  import { modalManager } from '$lib/managers/modal-manager.svelte';
  import ShortcutsModal from '$lib/modals/ShortcutsModal.svelte';
  import { user } from '$lib/stores/user.store';
  import { getConfig, type SystemConfigDto } from '@immich/sdk';
  import { Container, IconButton } from '@immich/ui';
  import { mdiKeyboard } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  let config: SystemConfigDto | undefined = $state(undefined);

  $effect(() => {
    if ($user.isAdmin) {
      getConfig()
        .then((res) => {
          config = res;
        })
        .catch((error) => console.warn(error));
    } else {
      config = undefined;
    }
  });
</script>

<UserPageLayout title={data.meta.title}>
  {#snippet buttons()}
    <IconButton
      shape="round"
      color="secondary"
      variant="ghost"
      icon={mdiKeyboard}
      aria-label={$t('show_keyboard_shortcuts')}
      onclick={() => modalManager.show(ShortcutsModal, {})}
    />
  {/snippet}
  <Container size="medium" center>
    <UserSettingsList {config} keys={data.keys} sessions={data.sessions} />
  </Container>
</UserPageLayout>
