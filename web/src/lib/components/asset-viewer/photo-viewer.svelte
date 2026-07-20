<script lang="ts">
  import { shortcuts } from '$lib/actions/shortcut';
  import { thumbhash } from '$lib/actions/thumbhash';
  import { zoomImageAction } from '$lib/actions/zoom-image';
  import AdaptiveImage from '$lib/components/AdaptiveImage.svelte';
  import FaceEditor from '$lib/components/asset-viewer/face-editor/face-editor.svelte';
  import OcrBoundingBox from '$lib/components/asset-viewer/ocr-bounding-box.svelte';
  import AssetViewerEvents from '$lib/components/AssetViewerEvents.svelte';
  import { assetViewerManager } from '$lib/managers/asset-viewer-manager.svelte';
  import { authManager } from '$lib/managers/auth-manager.svelte';
  import { castManager } from '$lib/managers/cast-manager.svelte';
  import { Route } from '$lib/route';
  import { ocrManager } from '$lib/stores/ocr.svelte';
  import { boundingBoxesArray, type Faces } from '$lib/stores/people.store';
  import { SlideshowLook, SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
  import { handlePromiseError } from '$lib/utils';
  import { canCopyImageToClipboard, copyImageToClipboard } from '$lib/utils/asset-utils';
  import { getNaturalSize, scaleToFit, type Size } from '$lib/utils/container-utils';
  import { handleError } from '$lib/utils/handle-error';
  import { getOcrBoundingBoxes } from '$lib/utils/ocr-utils';
  import { getBoundingBox, type BoundingBox } from '$lib/utils/people-utils';
  import { type PersonWithFacesResponseDto, type SharedLinkResponseDto } from '@immich/sdk';
  import { toastManager } from '@immich/ui';
  import { onDestroy, untrack } from 'svelte';
  import { useSwipe, type SwipeCustomEvent } from 'svelte-gestures';
  import { t } from 'svelte-i18n';
  import type { AssetCursor } from './asset-viewer.svelte';

  type Props = {
    cursor: AssetCursor;
    element?: HTMLDivElement;
    sharedLink?: SharedLinkResponseDto;
    onReady?: () => void;
    onError?: () => void;
    onSwipe?: (event: SwipeCustomEvent) => void;
  };

  let { cursor, element = $bindable(), sharedLink, onReady, onError, onSwipe }: Props = $props();

  const { slideshowState, slideshowLook } = slideshowStore;
  const asset = $derived(cursor.current);

  let visibleImageReady: boolean = $state(false);

  let previousAssetId: string | undefined;
  $effect.pre(() => {
    const id = asset.id;
    if (id === previousAssetId) {
      return;
    }
    previousAssetId = id;
    untrack(() => {
      assetViewerManager.resetZoomState();
      visibleImageReady = false;
      $boundingBoxesArray = [];
    });
  });

  onDestroy(() => {
    $boundingBoxesArray = [];
  });

  let containerWidth = $state(0);
  let containerHeight = $state(0);

  const container = $derived({
    width: containerWidth,
    height: containerHeight,
  });

  const overlaySize = $derived.by((): Size => {
    if (!assetViewerManager.imgRef || !visibleImageReady) {
      return { width: 0, height: 0 };
    }

    return scaleToFit(getNaturalSize(assetViewerManager.imgRef), { width: containerWidth, height: containerHeight });
  });

  const highlightedBoxes = $derived(getBoundingBox($boundingBoxesArray, overlaySize));
  const isHighlighting = $derived(highlightedBoxes.length > 0);

  let visibleBoxes = $state<BoundingBox[]>([]);
  $effect(() => {
    if (isHighlighting) {
      visibleBoxes = highlightedBoxes;
    }
  });

  const ocrBoxes = $derived(ocrManager.showOverlay ? getOcrBoundingBoxes(ocrManager.data, overlaySize) : []);

  const onCopy = async () => {
    if (!canCopyImageToClipboard() || !assetViewerManager.imgRef) {
      return;
    }

    try {
      await copyImageToClipboard(assetViewerManager.imgRef);
      toastManager.info($t('copied_image_to_clipboard'));
    } catch (error) {
      handleError(error, $t('copy_error'));
    }
  };

  const onZoom = () => {
    const targetZoom = assetViewerManager.zoom > 1 ? 1 : 2;
    assetViewerManager.animatedZoom(targetZoom);
  };

  const onPlaySlideshow = () => ($slideshowState = SlideshowState.PlaySlideshow);

  $effect(() => {
    if (assetViewerManager.isFaceEditMode && assetViewerManager.zoom > 1) {
      onZoom();
    }
  });

  // TODO move to action + command palette
  const onCopyShortcut = (event: KeyboardEvent) => {
    if (globalThis.getSelection()?.type === 'Range') {
      return;
    }
    event.preventDefault();

    handlePromiseError(onCopy());
  };

  let currentPreviewUrl = $state<string>();

  const onUrlChange = (url: string) => {
    currentPreviewUrl = url;
  };

  $effect(() => {
    if (currentPreviewUrl) {
      void cast(currentPreviewUrl);
    }
  });

  const cast = async (url: string) => {
    if (!url || !castManager.isCasting) {
      return;
    }
    const fullUrl = new URL(url, globalThis.location.href);

    try {
      await castManager.loadMedia(fullUrl.href);
    } catch (error) {
      handleError(error, 'Unable to cast');
      return;
    }
  };

  const blurredSlideshow = $derived(
    $slideshowState !== SlideshowState.None && $slideshowLook === SlideshowLook.BlurredBackground && !!asset.thumbhash,
  );

  let adaptiveImage = $state<HTMLDivElement | undefined>();

  type FaceOverlay = BoundingBox & {
    face: Faces;
    person: PersonWithFacesResponseDto;
    name: string;
  };

  const faceOverlays = $derived.by((): FaceOverlay[] => {
    if (
      assetViewerManager.isFaceEditMode ||
      ocrManager.showOverlay ||
      overlaySize.width === 0 ||
      overlaySize.height === 0
    ) {
      return [];
    }

    const facePeople: { face: Faces; person: PersonWithFacesResponseDto }[] = [];
    for (const person of asset.people ?? []) {
      for (const face of person.faces ?? []) {
        facePeople.push({ face, person });
      }
    }

    const boxes = getBoundingBox(
      facePeople.map(({ face }) => face),
      overlaySize,
    );

    return boxes.map((box, index) => ({
      ...box,
      face: facePeople[index].face,
      person: facePeople[index].person,
      name: facePeople[index].person.name,
    }));
  });

  const canOpenPerson = $derived(!authManager.isSharedLink);
  const previousRoute = Route.photos();

  const onFacePointerEnter = (face: Faces) => {
    $boundingBoxesArray = [face];
  };

  const onFacePointerLeave = () => {
    $boundingBoxesArray = [];
  };

  const stopZoomDblClick = (event: MouseEvent) => {
    event.stopPropagation();
  };
</script>

<AssetViewerEvents {onCopy} {onZoom} />

<svelte:document
  use:shortcuts={[
    { shortcut: { key: 'z' }, onShortcut: onZoom, preventDefault: true },
    { shortcut: { key: 's' }, onShortcut: onPlaySlideshow, preventDefault: true },
    { shortcut: { key: 'c', ctrl: true }, onShortcut: onCopyShortcut, preventDefault: false },
    { shortcut: { key: 'c', meta: true }, onShortcut: onCopyShortcut, preventDefault: false },
  ]}
/>

<div
  bind:this={element}
  class="relative h-full w-full select-none"
  bind:clientWidth={containerWidth}
  bind:clientHeight={containerHeight}
  role="presentation"
  ondblclick={onZoom}
  use:zoomImageAction={{ zoomTarget: adaptiveImage }}
  {...useSwipe((event) => onSwipe?.(event))}
>
  <AdaptiveImage
    {asset}
    {sharedLink}
    {container}
    objectFit={$slideshowState !== SlideshowState.None && $slideshowLook === SlideshowLook.Cover ? 'cover' : 'contain'}
    {onUrlChange}
    onImageReady={() => {
      visibleImageReady = true;
      onReady?.();
    }}
    onError={() => {
      onError?.();
      onReady?.();
    }}
    bind:imgRef={assetViewerManager.imgRef}
    bind:ref={adaptiveImage}
  >
    {#snippet backdrop()}
      {#if blurredSlideshow}
        <canvas
          use:thumbhash={{ base64ThumbHash: asset.thumbhash! }}
          class="absolute top-0 left-0 inset-s-0 h-dvh w-dvw"
        ></canvas>
      {/if}
    {/snippet}
    {#snippet overlays()}
      <div
        class="absolute inset-0 pointer-events-none transition-opacity duration-150"
        style:opacity={isHighlighting ? 1 : 0}
      >
        <svg class="absolute inset-0 w-full h-full">
          <defs>
            <mask id="face-dim-mask">
              <rect width="100%" height="100%" fill="white" />
              {#each visibleBoxes as box (box.id)}
                <rect x={box.left} y={box.top} width={box.width} height={box.height} fill="black" rx="8" />
              {/each}
            </mask>
          </defs>
          <rect width="100%" height="100%" fill="rgba(0,0,0,0.4)" mask="url(#face-dim-mask)" />
        </svg>
        {#each visibleBoxes as box (box.id)}
          {@const overlay = faceOverlays.find((item) => item.id === box.id)}
          <div
            class="absolute border-solid border-white border-3 rounded-lg"
            style="top: {box.top}px; left: {box.left}px; height: {box.height}px; width: {box.width}px;"
          ></div>
          {#if overlay?.name}
            <div
              aria-hidden="true"
              class="absolute bg-white/90 text-black px-2 py-1 rounded text-sm font-medium whitespace-nowrap shadow-lg"
              style="top: {box.top + box.height + 4}px; left: {box.left + box.width}px; transform: translateX(-100%);"
            >
              {overlay.name}
            </div>
          {/if}
        {/each}
      </div>

      {#each faceOverlays as overlay (overlay.id)}
        {@const label = overlay.name || $t('person')}
        {@const faceClass = `absolute rounded-lg pointer-events-auto ${canOpenPerson ? 'cursor-pointer' : ''}`}
        {@const faceStyle = `top: ${overlay.top}px; left: ${overlay.left}px; height: ${overlay.height}px; width: ${overlay.width}px;`}
        {#if canOpenPerson}
          <a
            href={Route.viewPerson(overlay.person, { previousRoute })}
            class={faceClass}
            style={faceStyle}
            data-overlay-interactive
            aria-label={label}
            onpointerenter={() => onFacePointerEnter(overlay.face)}
            onpointerleave={onFacePointerLeave}
            ondblclick={stopZoomDblClick}
          ></a>
        {:else}
          <!-- svelte-ignore a11y_no_static_element_interactions -->
          <div
            class={faceClass}
            style={faceStyle}
            data-overlay-interactive
            role="presentation"
            onpointerenter={() => onFacePointerEnter(overlay.face)}
            onpointerleave={onFacePointerLeave}
            ondblclick={stopZoomDblClick}
          ></div>
        {/if}
      {/each}

      {#each ocrBoxes as ocrBox (ocrBox.id)}
        <OcrBoundingBox {ocrBox} />
      {/each}
    {/snippet}
  </AdaptiveImage>

  {#if assetViewerManager.isFaceEditMode && assetViewerManager.imgRef}
    <FaceEditor htmlElement={assetViewerManager.imgRef} {containerWidth} {containerHeight} assetId={asset.id} />
  {/if}
</div>
