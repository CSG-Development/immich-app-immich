<script lang="ts">
  import seagatePersonalCloudLogoDark from '$lib/assets/seagate-personal-cloud-logo-dark.svg';
  import seagatePersonalCloudLogoLight from '$lib/assets/seagate-personal-cloud-logo-light.svg';
  import { Card, CardBody, CardHeader, Heading, Logo, Theme, themeManager, VStack, immichLogo } from '@immich/ui';
  import type { Snippet } from 'svelte';

  interface Props {
    title?: string;
    children?: Snippet;
    withHeader?: boolean;
    isLogin?: boolean;
  }

  let { title, children, withHeader = true, isLogin = false }: Props = $props();

  const theme = $derived(themeManager.value);
  const seagateLogo = $derived(
    theme === Theme.Light ? seagatePersonalCloudLogoLight : seagatePersonalCloudLogoDark,
  );
</script>

<section
  class="min-w-dvw flex min-h-dvh items-center justify-center relative {isLogin
    ? 'md:bg-neutral-200 dark:md:bg-neutral-800'
    : ''}"
>
  <Card
    color="secondary"
    class="w-full {isLogin
      ? 'm-0 max-w-[480px] min-h-dvh rounded-none border-0! shadow-none bg-transparent! dark:bg-transparent! md:m-2 md:min-h-[min(816px,100dvh-1rem)] md:rounded-[2rem] md:shadow-sm md:bg-white! dark:md:bg-neutral-900!'
      : 'm-2 max-w-lg border'}"
  >
    {#if withHeader}
      <CardHeader class={isLogin ? 'px-10 pt-12' : 'mt-6'}>
        {#if isLogin}
          <VStack gap={8} class="w-full">
            <img
              src={seagateLogo}
              alt="Seagate Personal Cloud"
              class="mx-auto h-12 w-auto object-contain"
            />
            <img src={immichLogo} alt="" class="mx-auto mt-2 h-48 w-48 object-contain" />
            {#if title}
              <Heading
                size="large"
                fontWeight="normal"
                class="mt-2 md:font-bold! text-black dark:text-white"
                tag="h1"
              >
                {title}
              </Heading>
            {/if}
          </VStack>
        {:else}
          <VStack>
            <Logo variant="icon" size="giant" />
            <Heading size="large" class="font-semibold" color="primary" tag="h1">{title}</Heading>
          </VStack>
        {/if}
      </CardHeader>
    {/if}

    <CardBody class={isLogin ? 'flex flex-1 flex-col px-10 pb-12 pt-10' : 'p-8'}>
      {@render children?.()}
    </CardBody>
  </Card>
</section>
