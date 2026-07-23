<script>
  // @ts-nocheck

  import { afterNavigate, goto } from '$app/navigation';
  import { page } from '$app/state';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { Route } from '$lib/route';
  import { getAssetMediaUrl } from '$lib/utils';
  import { urlToArrayBuffer } from '$lib/utils/asset-utils';
  import { fileUploadHandler } from '$lib/utils/file-uploader';
  import { AssetMediaSize, getAssetInfo } from '@immich/sdk';
  import { LoadingSpinner } from '@immich/ui';
  import { onMount } from 'svelte';
  /**
   * @type any
   */
  let target;
  let flutterState;
  /* let asset = $state(undefined); */

  const assetId = page.url.searchParams.get('assetId');

  let previousUrl = '';

  afterNavigate((nav) => {
    previousUrl = nav.from?.url.pathname || '';
  });

  const onFlutterAppLoaded = async (/** @type {Event} */ event) => {
    flutterState = event.detail;

    // The Flutter image editor decodes these bytes with the browser's image decoder,
    // which cannot handle formats like HEIC/HEIF. Request the fullsize media instead of
    // the original: the server returns the original for web-supported formats and a
    // browser-decodable (JPEG/WebP) version for everything else.
    const imageUrl = getAssetMediaUrl({ id: assetId, size: AssetMediaSize.Fullsize, edited: false });
    const imageBytes = await urlToArrayBuffer(imageUrl);

    globalThis.postMessage({ type: 'sendFile', file: imageBytes });
    flutterState.setImage(new Uint8Array(imageBytes));

    flutterState.onEditingComplete(onEditingComplete);
    flutterState.onEditorClosed(onEditorClosed);
  };

  const onEditingComplete = async () => {
    const uint8Array = flutterState.getImage();

    const asset = await getAssetInfo({ id: assetId, key: authManager.key });
    const lastDotIndex = asset.originalFileName.lastIndexOf('.');
    const fileNameWithoutExt =
      // eslint-disable-next-line unicorn/prefer-string-slice
      lastDotIndex === -1 ? asset.originalFileName : asset.originalFileName.substring(0, lastDotIndex);
    const resultFile = new File([uint8Array], `${fileNameWithoutExt}_${Date.now()}_edited.png`, { type: 'image/png' });
    await fileUploadHandler({ files: [resultFile] }).then(async () => {
      await goto(Route.photos(), { replaceState: true });
    });
  };

  const onEditorClosed = async () => {
    await (previousUrl ? goto(previousUrl, { replaceState: true }) : goto(Route.photos(), { replaceState: true }));
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
