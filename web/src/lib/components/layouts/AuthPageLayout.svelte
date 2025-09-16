<script lang="ts">
  import { Card, CardBody, CardHeader, Heading, Logo, VStack } from '@immich/ui';
  import type { Snippet } from 'svelte';
  interface Props {
    title?: string;
    children?: Snippet;
    withHeader?: boolean;
    isLogin?: boolean;
  }

  let { title, children, withHeader = true, isLogin = false }: Props = $props();
</script>

<section class="min-w-dvw flex min-h-dvh items-center justify-center relative">
  <Card color="secondary" class="w-full max-w-lg border m-2">
    {#if withHeader}
      <CardHeader class="mt-6">
        <VStack>
          <Logo variant={isLogin ? 'stacked' : 'icon'} size={isLogin ? 'stacked' : 'giant'} />
          {#if !isLogin}<Heading size="large" class="font-semibold" color="primary" tag="h1">{title}</Heading>{/if}
        </VStack>
      </CardHeader>
    {/if}

    <CardBody class="p-8">
      {@render children?.()}
    </CardBody>
  </Card>
</section>
