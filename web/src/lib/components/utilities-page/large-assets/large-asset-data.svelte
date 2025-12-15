<script lang="ts">
  import Thumbnail from '$lib/components/assets/thumbnail/thumbnail.svelte';
  import { getFileSize } from '$lib/utils/asset-utils';
  import { toTimelineAsset } from '$lib/utils/timeline-util';
  import { type AssetResponseDto } from '@immich/sdk';

  interface Props {
    asset: AssetResponseDto;
    onViewAsset: (asset: AssetResponseDto) => void;
  }

  let { asset, onViewAsset }: Props = $props();

  let boxWidth = $state(300);
</script>

<div
  class="w-full aspect-square rounded-xl transition-colors font-semibold text-xs bg-immich-bg-gray dark:bg-immich-dark-bg-gray p-1"
  bind:clientWidth={boxWidth}
>
  <div class="relative w-full h-full overflow-hidden rounded-lg">
    <Thumbnail asset={toTimelineAsset(asset)} readonly onClick={() => onViewAsset(asset)} thumbnailSize={boxWidth} />

    {#if !!asset.libraryId}
      <div class="absolute bottom-1 end-3 px-4 py-1 rounded-xl text-xs transition-colors bg-red-500">External</div>
    {/if}
  </div>

  <div class="text-center mt-4 px-4 text-sm font-medium truncate" title={asset.originalFileName}>
    {asset.originalFileName}
  </div>

  <div class="text-center">
    <p class="text-primary text-xl font-semibold py-3">{getFileSize(asset, 1)}</p>
  </div>
</div>
