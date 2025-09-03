<script>
  // @ts-nocheck

  import { afterNavigate, goto } from '$app/navigation';
  import { resolve } from '$app/paths';
  import { page } from '$app/state';
  import { AppRoute } from '$lib/constants';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { urlToArrayBuffer } from '$lib/utils/asset-utils';
  import { fileUploadHandler } from '$lib/utils/file-uploader';
  import { getAssetInfo, getBaseUrl } from '@immich/sdk';
  import { LoadingSpinner } from '@immich/ui';
  import { onMount } from 'svelte';
  /**
   * @type any
   */
  let target;
  let flutterState;
  /* let asset = $state(undefined); */

  const key = authManager.key;
  const assetId = page.url.searchParams.get('assetId');

  let previousUrl = '';

  afterNavigate((nav) => {
    previousUrl = nav.from?.url.pathname || '';
  });

  const onFlutterAppLoaded = async (/** @type {Event} */ event) => {
    flutterState = event.detail;

    const originalAsset = await urlToArrayBuffer(
      getBaseUrl() + `/assets/${assetId}/original` + (key ? `?key=${key}` : ''),
    );

    globalThis.postMessage({ type: 'sendFile', file: originalAsset });
    flutterState.setImage(new Uint8Array(originalAsset));

    flutterState.onEditingComplete(onEditingComplete);
    flutterState.onEditorClosed(onEditorClosed);
  };

  const onEditingComplete = async () => {
    const uint8Array = flutterState.getImage();

    const asset = await getAssetInfo({ id: assetId, key: authManager.key });
    const resultFile = new File([uint8Array], asset.originalFileName);
    await fileUploadHandler({ files: [resultFile] }).then(async () => {
      await goto(resolve(AppRoute.PHOTOS), { replaceState: true });
    });
  };

  const onEditorClosed = async () => {
    await (previousUrl
      ? goto(previousUrl, { replaceState: true })
      : goto(resolve(AppRoute.PHOTOS), { replaceState: true }));
  };

  function loadFlutterScript() {
    return new Promise((resolve, reject) => {
      const script = document.createElement('script');
      script.src = './flutter/flutter.js';
      script.addEventListener('load', () => resolve());
      script.addEventListener('error', (e) => reject(e));
      document.head.append(script);
    });
  }

  let isFlutterLoading = $state(true);

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
          isFlutterLoading = false;
          await appRunner.runApp();
        },
      });

      target.addEventListener('flutter-initialized', async (event) => {
        await onFlutterAppLoaded(event);
      });
    }
  });
</script>

<div class="flutter_target flex justify-center items-center" bind:this={target}>
  {#if isFlutterLoading}
    <LoadingSpinner size="giant" />
  {/if}
</div>

<style>
  .flutter_target {
    width: 100%;
    height: 100vh;
    background-color: #f2f2f2;
    border: 1px solid #000;
  }
</style>
