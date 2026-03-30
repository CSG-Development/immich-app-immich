<script lang="ts">
  import { type DownloadProgress, downloadManager } from '$lib/managers/download-manager.svelte';
  import { locale } from '$lib/stores/preferences.store';
  import { Heading, IconButton } from '@immich/ui';
  import { mdiClose } from '@mdi/js';
  import { t } from 'svelte-i18n';
  import { fly, slide } from 'svelte/transition';
  import { getByteUnitString } from '../../utils/byte-units';

  const abort = (downloadKey: string, download: DownloadProgress) => {
    download.abort?.abort();
    downloadManager.clear(downloadKey);
  };

  const calculateMargin = (percentage: number) => {
    switch (percentage) {
      case 13:
      case 14:
      case 86:
      case 87: {
        return '1.75px';
      }
      case 11:
      case 12:
      case 88:
      case 89: {
        return '1.5px';
      }
      case 9:
      case 10:
      case 90:
      case 91: {
        return '1.25px';
      }
      case 7:
      case 8:
      case 92:
      case 93: {
        return '1px';
      }
      case 5:
      case 6:
      case 94:
      case 95: {
        return '0.75px';
      }
      case 3:
      case 4:
      case 96:
      case 97: {
        return '0.5px';
      }
      case 1:
      case 2:
      case 98:
      case 99: {
        return '0.25px';
      }
      case 0:
      case 100: {
        return '0px';
      }
      default: {
        return '2px';
      }
    }
  };
</script>

{#if downloadManager.isDownloading}
  <div
    transition:fly={{ x: -100, duration: 350 }}
    class="fixed md:end-4 left-[50%] md:left-auto transform-[translateX(-50%)] md:transform-none bottom-1 md:top-24 z-70 max-h-[112px] w-[300px] rounded-lg p-4 bg-light dark:bg-immich-dark-gray-card"
  >
    <Heading class="text-xl font-bold" size="tiny">{$t('downloading')}</Heading>
    <div class="mt-3 flex max-h-[200px] flex-col overflow-y-auto text-sm">
      {#each Object.keys(downloadManager.assets) as downloadKey (downloadKey)}
        {@const download = downloadManager.assets[downloadKey]}
        <div class="mb-2 flex place-items-center" transition:slide>
          <div class="w-full pe-10">
            <div class="flex place-items-center justify-between gap-2 text-sm">
              <p class="truncate">{downloadKey}</p>
              {#if download.total}
                <p class="whitespace-nowrap">{getByteUnitString(download.total, $locale)}</p>
              {/if}
            </div>
            <div class="flex place-items-center justify-between">
              <div class="flex place-items-center w-46">
                <div
                  class="h-1 rounded-full bg-primary"
                  style={`width: ${download.percentage}%; margin-right: ${calculateMargin(download.percentage)}`}
                ></div>
                <div
                  class="h-1 rounded-full bg-neutral-200 dark:bg-neutral-600 flex justify-end"
                  style={`width: calc(${100 - download.percentage}%); margin-left: ${calculateMargin(download.percentage)}`}
                >
                  <div class="h-1 rounded-full w-1 bg-primary"></div>
                </div>
              </div>
              <p class="whitespace-nowrap text-right">
                <span class="text-primary font-medium">
                  {(download.percentage / 100).toLocaleString($locale, { style: 'percent' })}
                </span>
              </p>
            </div>
          </div>
          <div class="absolute end-4">
            <IconButton
              variant="ghost"
              shape="round"
              color="secondary"
              aria-label={$t('close')}
              onclick={() => abort(downloadKey, download)}
              size="tiny"
              class="[&_svg]:w-6 [&_svg]:h-6"
              icon={mdiClose}
            />
          </div>
        </div>
      {/each}
    </div>
  </div>
{/if}
