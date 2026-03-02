<script lang="ts">
  import Icon from '$lib/components/elements/icon.svelte';
  import {
    isComponentNotification,
    notificationController,
    NotificationType,
    type ComponentNotification,
    type Notification,
  } from '$lib/components/shared-components/notification/notification';
  import { themeManager } from '$lib/managers/theme-manager.svelte';
  import { Button, IconButton, Theme, type Color } from '@immich/ui';
  import { mdiCloseCircleOutline, mdiInformationOutline, mdiWindowClose } from '@mdi/js';
  import { onMount } from 'svelte';
  import { t } from 'svelte-i18n';
  import { fade } from 'svelte/transition';

  interface Props {
    notification: Notification | ComponentNotification;
  }

  const theme = $derived(themeManager.value);

  let { notification }: Props = $props();

  let icon = $derived(notification.type === NotificationType.Error ? mdiCloseCircleOutline : mdiInformationOutline);
  let hoverStyle = $derived(notification.action.type === 'discard' ? 'hover:cursor-pointer' : '');

  const backgroundColor: Record<NotificationType, string> = {
    [NotificationType.Info]: '#E4F2FE',
    [NotificationType.Error]: '#FBE8E6',
    [NotificationType.Warning]: '#FFF4CE',
  };

  const backgroundColorDark: Record<NotificationType, string> = {
    [NotificationType.Info]: '#03233F',
    [NotificationType.Error]: '#3B100D',
    [NotificationType.Warning]: '#433519',
  };

  const primaryColor: Record<NotificationType, string> = {
    [NotificationType.Info]: '#1976D2',
    [NotificationType.Error]: '#F44336',
    [NotificationType.Warning]: '#D08613',
  };

  const primaryColorDark: Record<NotificationType, string> = {
    [NotificationType.Info]: '#64B5F6',
    [NotificationType.Error]: '#F28F8C',
    [NotificationType.Warning]: '#FFD18D',
  };

  const colors: Record<NotificationType, Color> = {
    [NotificationType.Info]: 'primary',
    [NotificationType.Error]: 'danger',
    [NotificationType.Warning]: 'warning',
  };

  onMount(() => {
    const timeoutId = setTimeout(discard, notification.timeout);
    return () => clearTimeout(timeoutId);
  });

  const discard = () => {
    notificationController.removeNotificationById(notification.id);
  };

  const handleClick = () => {
    if (notification.action.type === 'discard') {
      discard();
    }
  };

  const handleButtonClick = () => {
    const button = notification.button;
    if (button) {
      discard();
      return notification.button?.onClick();
    }
  };
</script>

<!-- svelte-ignore a11y_no_static_element_interactions -->
<div
  transition:fade={{ duration: 250 }}
  style:background-color={theme === Theme.Light
    ? backgroundColor[notification.type]
    : backgroundColorDark[notification.type]}
  class="border mb-4 w-[300px] rounded-2xl p-4 shadow-md {hoverStyle}"
  onclick={handleClick}
  onkeydown={handleClick}
>
  <div class="flex justify-between h-6">
    <div class="flex place-items-center gap-2">
      <Icon
        path={icon}
        color={theme === Theme.Light ? primaryColor[notification.type] : primaryColorDark[notification.type]}
        size="20"
      />
      <h2
        style:color={theme === Theme.Light ? primaryColor[notification.type] : primaryColorDark[notification.type]}
        class="font-medium"
        data-testid="title"
      >
        {#if notification.type == NotificationType.Error}{$t('error')}
        {:else if notification.type == NotificationType.Warning}{$t('warning')}
        {:else if notification.type == NotificationType.Info}{$t('info')}{/if}
      </h2>
    </div>
    <IconButton
      variant="ghost"
      shape="round"
      color="secondary"
      icon={mdiWindowClose}
      aria-label={$t('close')}
      size="small"
      onclick={discard}
      aria-hidden={true}
      tabindex={-1}
    />
  </div>

  <p
    class="whitespace-pre-wrap ps-[28px] pe-[16px] text-sm text-secondary min-h-5 pt-2 wrap-break-word"
    data-testid="message"
  >
    {#if isComponentNotification(notification)}
      <notification.component.type {...notification.component.props} />
    {:else}
      {notification.message}
    {/if}
  </p>

  {#if notification.button}
    <p class="ps-[28px] mt-2.5 text-light">
      <Button
        size="small"
        color={colors[notification.type]}
        variant="ghost"
        class="px-0"
        onclick={handleButtonClick}
        aria-hidden="true"
        tabindex={-1}
      >
        {notification.button.text}
      </Button>
    </p>
  {/if}
</div>
