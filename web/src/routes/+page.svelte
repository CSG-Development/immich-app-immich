<script lang="ts">
  import { resolveRoute } from '$app/paths';
  import { AppRoute } from '$lib/constants';
  import { Button, Heading, Logo } from '@immich/ui';
  import { t } from 'svelte-i18n';
</script>

<section class="flex h-dvh w-dvw place-content-center place-items-center">
  <div class="flex max-w-[350px] flex-col place-items-center gap-10 text-center">
    <div class="flex place-content-center place-items-center">
      <Logo variant="icon" class="text-center" size="landing" />
    </div>
    <Heading size="giant" color="primary" tag="h1">{$t('welcome_to_immich')}</Heading>
    <Button href={resolveRoute(AppRoute.AUTH_REGISTER, {})} size="giant" shape="round">
      <span class="px-2 font-bold">{$t('getting_started')}</span>
    </Button>
  </div>
</section>
