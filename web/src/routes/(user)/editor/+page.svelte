<script>
  // @ts-nocheck

  import { goto } from '$app/navigation';
  import { resolveRoute } from '$app/paths';
  import { page } from '$app/state';
  import { AppRoute } from '$lib/constants';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { urlToArrayBuffer } from '$lib/utils/asset-utils';
  import { fileUploadHandler } from '$lib/utils/file-uploader';
  import { getBaseUrl } from '@immich/sdk';
  import { onMount } from 'svelte';
  /**
   * @type any
   */
  let target;
  let flutterState;
  /* let asset = $state(undefined); */

  const onFlutterAppLoaded = async (/** @type {Event} */ event) => {
    flutterState = event.detail;

    const key = authManager.key;
    const assetId = page.url.searchParams.get('assetId');
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
    let binaryString = '';
    for (const element of uint8Array) {
      // eslint-disable-next-line unicorn/prefer-code-point
      binaryString += String.fromCharCode(element);
    }
    const base64String = btoa(binaryString);

    const dataUrl = `data:image/jpeg;base64,${base64String}`;

    const imgElement = document.createElement('img');
    imgElement.src = dataUrl;
    /* document.body.append(imgElement); */
    console.log('onEditingComplete', dataUrl);
    const resultFile = new File([uint8Array], 'test.jpg');
    const result = await fileUploadHandler({ files: [resultFile] });
    console.log(result);
    await goto(resolveRoute(`${AppRoute.PHOTOS}/${result[0]}`, {}), { replaceState: true });
  };

  const onEditorClosed = () => {
    console.log('editorClosed');
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
        },
      });

      target.addEventListener('flutter-initialized', async (event) => {
        await onFlutterAppLoaded(event);
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
