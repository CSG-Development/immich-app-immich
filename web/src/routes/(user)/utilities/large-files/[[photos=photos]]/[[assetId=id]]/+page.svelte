<script lang="ts">
  import largeFilesUrl from '$lib/assets/large-files.svg';
  import type { Action } from '$lib/components/asset-viewer/actions/action';
  import UserPageLayout from '$lib/components/layouts/user-page-layout.svelte';
  import EmptyPlaceholder from '$lib/components/shared-components/empty-placeholder.svelte';
  import LargeAssetData from '$lib/components/utilities-page/large-assets/large-asset-data.svelte';
  import Portal from '$lib/elements/Portal.svelte';
  import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
  import { handlePromiseError } from '$lib/utils';
  import { formatPageTitleWithCount } from '$lib/utils/string-utils';
  import { getNextAsset, getPreviousAsset } from '$lib/utils/asset-utils';
  import { navigate } from '$lib/utils/navigation';
  import type { AssetResponseDto } from '@immich/sdk';
  import { t } from 'svelte-i18n';
  import { locale } from '$lib/stores/preferences.store';
  import type { PageData } from './$types';

  interface Props {
    data: PageData;
  }

  let { data }: Props = $props();

  let assets = $derived(data.assets);
  let asset = $derived(data.asset);

  $effect(() => {
    if (asset) {
      assetViewerManager.setAsset(asset);
    }
  });

  const onRandom = async () => {
    if (assets.length <= 0) {
      return undefined;
    }
    const index = Math.floor(Math.random() * assets.length);
    const asset = assets[index];
    await onViewAsset(asset);
    return asset;
  };

  const onAction = (payload: Action) => {
    if (payload.type == 'trash') {
      assets = assets.filter((a) => a.id != payload.asset.id);
      assetViewerManager.showAssetViewer(false);
    }
  };

  const onViewAsset = async (asset: AssetResponseDto) => {
    await navigate({ targetRoute: 'current', assetId: asset.id });
  };

  let assetCursor = $derived({
    current: assetViewerManager.asset!,
    nextAsset: getNextAsset(assets, assetViewerManager.asset),
    previousAsset: getPreviousAsset(assets, assetViewerManager.asset),
  });
</script>

<UserPageLayout
  title={formatPageTitleWithCount(data.meta.title, assets.length, $locale)}
  scrollbar={true}
>
  {#if assets && data.assets.length > 0}
    <div class="grid gap-2 grid-cols-2 sm:grid-cols-3 lg:grid-cols-4 xl:grid-cols-6 pt-2">
      {#each assets as asset (asset.id)}
        <LargeAssetData {asset} {onViewAsset} />
      {/each}
    </div>
  {:else}
    <EmptyPlaceholder text={$t('no_assets_to_show')} src={largeFilesUrl} />
  {/if}
</UserPageLayout>

{#if assetViewerManager.isViewing}
  {#await import('$lib/components/asset-viewer/asset-viewer.svelte') then { default: AssetViewer }}
    <Portal target="body">
      <AssetViewer
        bind:cursor={assetCursor}
        showNavigation={assets.length > 1}
        {onRandom}
        {onAction}
        onClose={() => {
          assetViewerManager.showAssetViewer(false);
          handlePromiseError(navigate({ targetRoute: 'current', assetId: null }));
        }}
      />
    </Portal>
  {/await}
{/if}
