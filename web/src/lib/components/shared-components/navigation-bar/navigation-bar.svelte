<script lang="ts" module>
  export const menuButtonId = 'top-menu-button';
</script>

<script lang="ts">
  import { resolveRoute } from '$app/paths';
  import { page } from '$app/state';
  import { clickOutside } from '$lib/actions/click-outside';
  import SkipLink from '$lib/components/elements/buttons/skip-link.svelte';
  import HelpAndFeedbackModal from '$lib/components/shared-components/help-and-feedback-modal.svelte';
  import ImmichLogo from '$lib/components/shared-components/immich-logo.svelte';
  import NotificationPanel from '$lib/components/shared-components/navigation-bar/notification-panel.svelte';
  import SearchBar from '$lib/components/shared-components/search-bar/search-bar.svelte';
  import { AppRoute } from '$lib/constants';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { mobileDevice } from '$lib/stores/mobile-device.svelte';
  import { notificationManager } from '$lib/stores/notification-manager.svelte';
  import { featureFlags } from '$lib/stores/server-config.store';
  import { sidebarStore } from '$lib/stores/sidebar.svelte';
  import { user } from '$lib/stores/user.store';
  import { userInteraction } from '$lib/stores/user.svelte';
  import { getAboutInfo, type ServerAboutResponseDto } from '@immich/sdk';
  import { Button, IconButton } from '@immich/ui';
  import { mdiBellBadge, mdiBellOutline, mdiHelpCircleOutline, mdiMagnify, mdiMenu, mdiTrayArrowUp } from '@mdi/js';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import ThemeButton from '../theme-button.svelte';
  import UserAvatar from '../user-avatar.svelte';
  import AccountInfoPanel from './account-info-panel.svelte';

  interface Props {
    showUploadButton?: boolean;
    onUploadClick: () => void;
  }

  let { showUploadButton = true, onUploadClick }: Props = $props();

  let shouldShowAccountInfoPanel = $state(false);
  let shouldShowHelpPanel = $state(false);
  let shouldShowNotificationPanel = $state(false);
  let innerWidth: number = $state(0);
  const hasUnreadNotifications = $derived(notificationManager.notifications.length > 0);

  let info: ServerAboutResponseDto | undefined = $state();

  onMount(async () => {
    info = userInteraction.aboutInfo ?? (await getAboutInfo());
  });
</script>

<svelte:window bind:innerWidth />

{#if shouldShowHelpPanel && info}
  <HelpAndFeedbackModal onClose={() => (shouldShowHelpPanel = false)} {info} />
{/if}

<nav id="dashboard-navbar" class="z-auto max-md:h-[var(--navbar-height-md)] h-[var(--navbar-height)] w-dvw text-sm">
  <SkipLink text={$t('skip_to_content')} />
  <div
    class="grid h-full grid-cols-[theme(spacing.32)_auto] items-center border-b bg-immich-bg py-2 dark:border-b-immich-dark-gray dark:bg-immich-dark-bg sidebar:grid-cols-[theme(spacing.64)_auto]"
  >
    <div class="flex flex-row gap-1 mx-4 items-center">
      <IconButton
        id={menuButtonId}
        shape="round"
        color="secondary"
        variant="ghost"
        size="medium"
        aria-label={$t('main_menu')}
        icon={mdiMenu}
        onclick={() => {
          sidebarStore.toggle();
        }}
        onmousedown={(event: MouseEvent) => {
          if (sidebarStore.isOpen) {
            // stops event from reaching the default handler when clicking outside of the sidebar
            event.stopPropagation();
          }
        }}
        class="sidebar:hidden"
      />
      <a data-sveltekit-preload-data="hover" href={resolveRoute(AppRoute.PHOTOS, {})}>
        <ImmichLogo class="max-md:h-[48px] h-[50px]" noText={!mobileDevice.isFullSidebar} />
      </a>
    </div>
    <div class="flex justify-between gap-4 lg:gap-8 pe-6">
      <div class="hidden w-full max-w-5xl flex-1 tall:ps-0 sm:block">
        {#if $featureFlags.search}
          <SearchBar grayTheme={true} />
        {/if}
      </div>

      <section class="flex place-items-center justify-end gap-1 md:gap-2 w-full sm:w-auto">
        {#if $featureFlags.search}
          <IconButton
            color="secondary"
            shape="round"
            variant="ghost"
            size="medium"
            icon={mdiMagnify}
            href={resolveRoute(AppRoute.SEARCH, {})}
            id="search-button"
            class="sm:hidden"
            aria-label={$t('go_to_search')}
          />
        {/if}

        {#if !page.url.pathname.includes('/admin') && showUploadButton}
          <Button
            leadingIcon={mdiTrayArrowUp}
            onclick={onUploadClick}
            class="hidden lg:flex"
            variant="ghost"
            size="medium"
            color="secondary"
            >{$t('upload')}
          </Button>
          <IconButton
            color="secondary"
            shape="round"
            variant="ghost"
            size="medium"
            onclick={onUploadClick}
            title={$t('upload')}
            aria-label={$t('upload')}
            icon={mdiTrayArrowUp}
            class="lg:hidden"
          />
        {/if}

        <ThemeButton padding="2" />

        <div
          use:clickOutside={{
            onEscape: () => (shouldShowHelpPanel = false),
          }}
        >
          <IconButton
            shape="round"
            color="secondary"
            variant="ghost"
            size="medium"
            icon={mdiHelpCircleOutline}
            onclick={() => (shouldShowHelpPanel = !shouldShowHelpPanel)}
            aria-label={$t('support_and_feedback')}
          />
        </div>

        <div
          use:clickOutside={{
            onOutclick: () => (shouldShowNotificationPanel = false),
            onEscape: () => (shouldShowNotificationPanel = false),
          }}
        >
          <IconButton
            shape="round"
            color={hasUnreadNotifications ? 'primary' : 'secondary'}
            variant="ghost"
            size="medium"
            icon={hasUnreadNotifications ? mdiBellBadge : mdiBellOutline}
            onclick={() => (shouldShowNotificationPanel = !shouldShowNotificationPanel)}
            aria-label={$t('notifications')}
          />

          {#if shouldShowNotificationPanel}
            <NotificationPanel />
          {/if}
        </div>

        <div
          use:clickOutside={{
            onOutclick: () => (shouldShowAccountInfoPanel = false),
            onEscape: () => (shouldShowAccountInfoPanel = false),
          }}
        >
          <button
            type="button"
            class="flex ps-2"
            onclick={() => (shouldShowAccountInfoPanel = !shouldShowAccountInfoPanel)}
            title={`${$user.name} (${$user.email})`}
          >
            {#key $user}
              <UserAvatar user={$user} size="md" showTitle={false} interactive />
            {/key}
          </button>

          {#if shouldShowAccountInfoPanel}
            <AccountInfoPanel onLogout={() => authManager.logout()} />
          {/if}
        </div>
      </section>
    </div>
  </div>
</nav>
