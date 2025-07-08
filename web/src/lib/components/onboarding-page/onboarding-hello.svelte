<script lang="ts">
  import Button from '$lib/components/elements/buttons/button.svelte';
  import Icon from '$lib/components/elements/icon.svelte';
  import { themeManager } from '$lib/managers/theme-manager.svelte';
  import { user } from '$lib/stores/user.store';
  import { Logo } from '@immich/ui';
  import { mdiArrowRight } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import OnboardingCard from './onboarding-card.svelte';

  interface Props {
    onDone: () => void;
  }

  let { onDone }: Props = $props();
</script>

<OnboardingCard>
  <Logo class="h-[50px]" variant="icon" appTheme={themeManager.value} />
  <p class="font-medium text-6xl my-6 text-immich-primary dark:text-immich-dark-primary">
    {$t('onboarding_welcome_user', { values: { user: $user.name } })}
  </p>
  <p class="text-3xl pb-6 font-light">{$t('onboarding_welcome_description')}</p>

  <div class="w-full flex place-content-end">
    <Button class="flex gap-2 place-content-center" onclick={() => onDone()}>
      <p>{$t('theme')}</p>
      <Icon path={mdiArrowRight} size="18" />
    </Button>
  </div>
</OnboardingCard>
