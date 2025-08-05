<script>
  // @ts-nocheck

  import { page } from '$app/state';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { urlToArrayBuffer } from '$lib/utils/asset-utils';
  import { getBaseUrl } from '@immich/sdk';
  import { onMount } from 'svelte';
  /**
   * @type any
   */
  let target;

  function loadFlutterScript() {
    return new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = './flutter/flutter.js';
      script.addEventListener('load', () => resolve());
      script.addEventListener('error', (e) => reject(e));
      document.head.append(script);
    });
  }

  onMount(async () => {
    await loadFlutterScript();

    if (globalThis._flutter) {
      globalThis._flutter.loader.loadEntrypoint({
        entrypointUrl: './flutter/main.dart.js',
        onEntrypointLoaded: async (engineInitializer) => {
          let appRunner = await engineInitializer.initializeEngine({
            hostElement: target,
            assetBase: './flutter/',
          });
          await appRunner.runApp();

          const key = authManager.key;
          const assetId = page.url.searchParams.get('assetId');
          const originalAsset = await urlToArrayBuffer(
            getBaseUrl() + `/assets/${assetId}/original` + (key ? `?key=${key}` : ''),
          );

          globalThis.postMessage({ type: 'sendFile', file: originalAsset });
        },
      });
    }
  });
</script>

<div class="flutter_target" bind:this={target}></div>

<style>
  .flutter_target {
    width: 100%;
    height: 100vh;
    background-color: #f2f2f2;
    border: 1px solid #000;
  }
</style>
