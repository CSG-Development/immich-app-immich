<script lang="ts" module>
  export type Size = 'full' | 'sm' | 'md' | 'lg' | 'xl' | 'xxl' | 'xxxl';
</script>

<script lang="ts">
  import { getProfileImageUrl } from '$lib/utils';
  import { type UserAvatarColor } from '@immich/sdk';
  import { t } from 'svelte-i18n';

  interface User {
    id: string;
    name: string;
    email: string;
    profileImagePath: string;
    avatarColor: UserAvatarColor;
    profileChangedAt: string;
  }

  interface Props {
    user: User;
    size?: Size;
    interactive?: boolean;
    noTitle?: boolean;
    label?: string | undefined;
  }

  let { user, size = 'full', interactive = false, noTitle = false, label = undefined }: Props = $props();

  let img: HTMLImageElement | undefined = $state();
  let showFallback = $state(true);

  const tryLoadImage = async () => {
    try {
      await img?.decode();
      showFallback = false;
    } catch {
      showFallback = true;
    }
  };

  const colorClasses: Record<UserAvatarColor, string> = {
    primary: 'bg-primary/12 dark:bg-primary/24 text-primary',
    pink: 'bg-pink-400/12 dark:bg-pink-400/24 text-pink-400',
    red: 'bg-red-500/12 dark:bg-red-500/24 text-red-500',
    yellow: 'bg-yellow-500/12 dark:bg-yellow-500/24 text-yellow-500',
    blue: 'bg-blue-500/12 dark:bg-blue-500/24 text-blue-500',
    green: 'bg-green-600/12 dark:bg-green-600/24 text-green-600',
    purple: 'bg-purple-600/12 dark:bg-purple-600/24 text-purple-600',
    orange: 'bg-orange-600/12 dark:bg-orange-600/24 text-orange-600',
    gray: 'bg-gray-600/12 dark:bg-gray-400/24 text-gray-600 dark:text-gray-400',
    amber: 'bg-amber-600/12 dark:bg-amber-600/24 text-amber-600',
  };

  const sizeClasses: Record<Size, string> = {
    full: 'w-full h-full',
    sm: 'w-7 h-7',
    md: 'w-10 h-10',
    lg: 'w-12 h-12',
    xl: 'w-16 h-16',
    xxl: 'w-24 h-24',
    xxxl: 'w-28 h-28',
  };

  $effect(() => {
    if (img && user) {
      tryLoadImage().catch(console.error);
    }
  });

  let colorClass = $derived(colorClasses[user.avatarColor]);
  let sizeClass = $derived(sizeClasses[size]);
  let title = $derived(label ?? `${user.name} (${user.email})`);
  let interactiveClass = $derived(interactive ? 'transition-colors' : '');
</script>

<figure class="{sizeClass} {colorClass} {interactiveClass} overflow-hidden shadow-md rounded-full">
  {#if user.profileImagePath}
    <img
      bind:this={img}
      src={getProfileImageUrl(user)}
      alt={$t('profile_image_of_user', { values: { user: title } })}
      class="h-full w-full object-cover"
      class:hidden={showFallback}
      draggable="false"
      title={noTitle ? undefined : title}
    />
  {/if}
  {#if showFallback}
    <span
      class="uppercase flex h-full w-full select-none items-center justify-center"
      class:text-xs={size === 'sm'}
      class:text-lg={size === 'lg'}
      class:text-xl={size === 'xl'}
      class:text-2xl={size === 'xxl'}
      class:text-3xl={size === 'xxxl'}
    >
      {user.name[0] || ''}
    </span>
  {/if}
</figure>
