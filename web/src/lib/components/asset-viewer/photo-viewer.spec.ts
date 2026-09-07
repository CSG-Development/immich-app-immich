import { getAnimateMock } from '$lib/__mocks__/animate.mock';
import PhotoViewer from '$lib/components/asset-viewer/photo-viewer.svelte';
import { SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
import * as utils from '$lib/utils';
import { AssetMediaSize } from '@immich/sdk';
import { assetFactory } from '@test-data/factories/asset-factory';
import { sharedLinkFactory } from '@test-data/factories/shared-link-factory';
import { render } from '@testing-library/svelte';
import type { MockInstance } from 'vitest';

class ResizeObserver {
  observe() {}
  unobserve() {}
  disconnect() {}
}

globalThis.ResizeObserver = ResizeObserver;

vi.mock('$lib/utils', async (originalImport) => {
  const meta = await originalImport<typeof import('$lib/utils')>();
  return {
    ...meta,
    getAssetOriginalUrl: vi.fn(),
    getAssetThumbnailUrl: vi.fn(),
  };
});

describe('PhotoViewer component', () => {
  let getAssetOriginalUrlSpy: MockInstance;
  let getAssetThumbnailUrlSpy: MockInstance;

  beforeAll(() => {
    getAssetOriginalUrlSpy = vi.spyOn(utils, 'getAssetOriginalUrl');
    getAssetThumbnailUrlSpy = vi.spyOn(utils, 'getAssetThumbnailUrl');

    vi.stubGlobal('cast', {
      framework: {
        CastState: {
          NO_DEVICES_AVAILABLE: 'NO_DEVICES_AVAILABLE',
        },
        RemotePlayer: vi.fn().mockImplementation(() => ({})),
        RemotePlayerEventType: {
          ANY_CHANGE: 'anyChanged',
        },
        RemotePlayerController: vi.fn().mockImplementation(() => ({ addEventListener: vi.fn() })),
        CastContext: {
          getInstance: vi.fn().mockImplementation(() => ({ setOptions: vi.fn(), addEventListener: vi.fn() })),
        },
        CastContextEventType: {
          SESSION_STATE_CHANGED: 'sessionstatechanged',
          CAST_STATE_CHANGED: 'caststatechanged',
        },
      },
    });
    vi.stubGlobal('chrome', {
      cast: { media: { PlayerState: { IDLE: 'IDLE' } }, AutoJoinPolicy: { ORIGIN_SCOPED: 'origin_scoped' } },
    });
  });

  beforeEach(() => {
    Element.prototype.animate = getAnimateMock();
  });

  afterEach(() => {
    vi.resetAllMocks();
    slideshowStore.slideshowState.set(SlideshowState.None);
    slideshowStore.slideshowTransition.set(true);
  });

  it('loads the thumbnail', () => {
    const asset = assetFactory.build({ originalPath: 'image.jpg', originalMimeType: 'image/jpeg' });
    render(PhotoViewer, { cursor: { current: asset } });

    expect(getAssetThumbnailUrlSpy).toBeCalledWith({
      id: asset.id,
      size: AssetMediaSize.Preview,
      cacheKey: asset.thumbhash,
    });
    expect(getAssetOriginalUrlSpy).not.toBeCalled();
  });

  it('loads the original image for gifs', () => {
    const asset = assetFactory.build({ originalPath: 'image.gif', originalMimeType: 'image/gif' });
    render(PhotoViewer, { cursor: { current: asset } });

    expect(getAssetThumbnailUrlSpy).not.toBeCalled();
    expect(getAssetOriginalUrlSpy).toBeCalledWith({ id: asset.id, cacheKey: asset.thumbhash });
  });

  it('loads original for shared link when download permission is true and showMetadata permission is true', () => {
    const asset = assetFactory.build({ originalPath: 'image.gif', originalMimeType: 'image/gif' });
    const sharedLink = sharedLinkFactory.build({ allowDownload: true, showMetadata: true, assets: [asset] });
    render(PhotoViewer, { cursor: { current: asset }, sharedLink });

    expect(getAssetThumbnailUrlSpy).not.toBeCalled();
    expect(getAssetOriginalUrlSpy).toBeCalledWith({ id: asset.id, cacheKey: asset.thumbhash });
  });

  it('not loads original image when shared link download permission is false', () => {
    const asset = assetFactory.build({ originalPath: 'image.gif', originalMimeType: 'image/gif' });
    const sharedLink = sharedLinkFactory.build({ allowDownload: false, assets: [asset] });
    render(PhotoViewer, { cursor: { current: asset }, sharedLink });

    expect(getAssetThumbnailUrlSpy).toBeCalledWith({
      id: asset.id,
      size: AssetMediaSize.Preview,
      cacheKey: asset.thumbhash,
    });

    expect(getAssetOriginalUrlSpy).not.toBeCalled();
  });

  it('not loads original image when shared link showMetadata permission is false', () => {
    const asset = assetFactory.build({ originalPath: 'image.gif', originalMimeType: 'image/gif' });
    const sharedLink = sharedLinkFactory.build({ showMetadata: false, assets: [asset] });
    render(PhotoViewer, { cursor: { current: asset }, sharedLink });

    expect(getAssetThumbnailUrlSpy).toBeCalledWith({
      id: asset.id,
      size: AssetMediaSize.Preview,
      cacheKey: asset.thumbhash,
    });

    expect(getAssetOriginalUrlSpy).not.toBeCalled();
  });

  it('does not fade between photos outside of a slideshow', () => {
    const asset = assetFactory.build({ originalPath: 'image.jpg', originalMimeType: 'image/jpeg' });
    const { getByTestId } = render(PhotoViewer, { cursor: { current: asset } });

    expect(getByTestId('photo-viewer-slide')).toHaveAttribute('data-fade-transition', 'false');
  });

  it('fades between photos when slideshow transition is enabled', () => {
    slideshowStore.slideshowState.set(SlideshowState.PlaySlideshow);
    slideshowStore.slideshowTransition.set(true);

    const asset = assetFactory.build({ originalPath: 'image.jpg', originalMimeType: 'image/jpeg' });
    const { getByTestId } = render(PhotoViewer, { cursor: { current: asset } });

    expect(getByTestId('photo-viewer-slide')).toHaveAttribute('data-fade-transition', 'true');
  });

  it('does not fade between photos when slideshow transition is disabled', () => {
    slideshowStore.slideshowState.set(SlideshowState.PlaySlideshow);
    slideshowStore.slideshowTransition.set(false);

    const asset = assetFactory.build({ originalPath: 'image.jpg', originalMimeType: 'image/jpeg' });
    const { getByTestId } = render(PhotoViewer, { cursor: { current: asset } });

    expect(getByTestId('photo-viewer-slide')).toHaveAttribute('data-fade-transition', 'false');
  });

  it('keeps the previous photo visible while fading to the next slideshow photo', async () => {
    slideshowStore.slideshowState.set(SlideshowState.PlaySlideshow);
    slideshowStore.slideshowTransition.set(true);

    const first = assetFactory.build({ originalPath: 'image.jpg', originalMimeType: 'image/jpeg' });
    const second = assetFactory.build({ originalPath: 'image.jpg', originalMimeType: 'image/jpeg' });
    const { rerender, getAllByTestId } = render(PhotoViewer, { cursor: { current: first } });

    await rerender({ cursor: { current: second } });

    expect(getAllByTestId('photo-viewer-slide')).toHaveLength(2);
  });

  it('replaces the photo immediately when slideshow transition is disabled', async () => {
    slideshowStore.slideshowState.set(SlideshowState.PlaySlideshow);
    slideshowStore.slideshowTransition.set(false);

    const first = assetFactory.build({ originalPath: 'image.jpg', originalMimeType: 'image/jpeg' });
    const second = assetFactory.build({ originalPath: 'image.jpg', originalMimeType: 'image/jpeg' });
    const { rerender, getAllByTestId } = render(PhotoViewer, { cursor: { current: first } });

    await rerender({ cursor: { current: second } });

    expect(getAllByTestId('photo-viewer-slide')).toHaveLength(1);
  });
});
