<script lang="ts">
  import Portal from '$lib/elements/Portal.svelte';
  import { t } from 'svelte-i18n';
  import { flip } from 'svelte/animate';
  import { quintOut } from 'svelte/easing';
  import { fade } from 'svelte/transition';
  import { notificationController } from './notification';
  import NotificationCard from './notification-card.svelte';

  const { notificationList } = notificationController;
</script>

<Portal>
  <div role="status" aria-relevant="additions" aria-label={$t('notifications')}>
    {#if $notificationList.length > 0}
      <section
        transition:fade={{ duration: 250 }}
        id="notification-list"
        class="fixed md:end-5 left-[50%] md:left-auto transform-[translateX(-50%)] md:transform-none -bottom-3 md:top-[80px] z-70"
      >
        {#each $notificationList as notification (notification.id)}
          <div animate:flip={{ duration: 250, easing: quintOut }}>
            <NotificationCard {notification} />
          </div>
        {/each}
      </section>
    {/if}
  </div>
</Portal>
