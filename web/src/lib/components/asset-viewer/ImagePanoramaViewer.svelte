<script lang="ts">
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { getAssetUrl } from '$lib/utils';
  import { AssetMediaSize, viewAsset, type AssetResponseDto } from '@immich/sdk';
  import { LoadingSpinner } from '@immich/ui';
  import { fade } from 'svelte/transition';
  import PhotoViewer from './PhotoViewer.svelte';

  type Props = {
    asset: AssetResponseDto;
  };

  let { asset }: Props = $props();

  const assetId = $derived(asset.id);
  let useFlatFallback = $state(false);

  const loadAssetData = async (id: string) => {
    const data = await viewAsset({ ...authManager.params, id, size: AssetMediaSize.Preview });
    return URL.createObjectURL(data);
  };
</script>

<div transition:fade={{ duration: 150 }} class="flex h-full place-content-center place-items-center select-none">
  {#if useFlatFallback}
    <!-- Mis-tagged equirectangular / broken PSV: show as a normal photo instead of a blank viewer -->
    <PhotoViewer cursor={{ current: asset }} />
  {:else}
    {#await Promise.all([loadAssetData(assetId), import('./PhotoSphereViewerAdapter.svelte')])}
      <LoadingSpinner />
    {:then [data, { default: PhotoSphereViewer }]}
      <PhotoSphereViewer
        panorama={data}
        originalPanorama={getAssetUrl({ asset, forceOriginal: true })}
        onError={() => {
          useFlatFallback = true;
        }}
      />
    {:catch}
      <!-- Load/init failure — fall back to flat photo viewer for this one asset -->
      <PhotoViewer cursor={{ current: asset }} />
    {/await}
  {/if}
</div>
