<script lang="ts">
  import { mobileDevice } from '$lib/stores/mobile-device.svelte';
  import { Logo } from '@immich/ui';
</script>

<a data-sveltekit-preload-data="hover" class="h-[50px] ms-4 flex items-center" href="/">
  <Logo
    class={`${mobileDevice.maxMd ? 'h-[35px] ms-[5px]' : 'h-[50px]'} max-w-none md:w-auto md:max-w-full`}
    variant={mobileDevice.maxMd ? 'icon' : 'inline'}
  />
</a>
