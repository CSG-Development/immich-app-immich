import { getAnimateMock } from '$lib/__mocks__/animate.mock';
import { getResizeObserverMock } from '$lib/__mocks__/resize-observer.mock';
import PhotoViewer from '$lib/components/asset-viewer/PhotoViewer.svelte';
import { SlideshowState, slideshowStore } from '$lib/stores/slideshow.store';
import * as utils from '$lib/utils';
import { assetFactory } from '@test-data/factories/asset-factory';
import { sharedLinkFactory } from '@test-data/factories/shared-link-factory';
import { render } from '@testing-library/svelte';

vi.stubGlobal('ResizeObserver', getResizeObserverMock());

vi.mock('$lib/utils', async (originalImport) => {
  const meta = await originalImport<typeof import('$lib/utils')>();
  return {
    ...meta,
    getAssetUrls: vi.fn(),
  };
});

describe('PhotoViewer component', () => {
  const getAssetUrlsSpy = vi.spyOn(utils, 'getAssetUrls');

  beforeAll(() => {
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
    getAssetUrlsSpy.mockReturnValue({
      thumbnail: '/thumbnail.jpg',
      preview: '/preview.jpg',
      original: '/original.jpg',
    });
  });

  afterEach(() => {
    vi.resetAllMocks();
    slideshowStore.slideshowState.set(SlideshowState.None);
    slideshowStore.slideshowTransition.set(true);
  });

  it('resolves the asset urls for the current asset', () => {
    const asset = assetFactory.build({ originalPath: 'image.jpg', originalMimeType: 'image/jpeg' });
    render(PhotoViewer, { cursor: { current: asset } });

    expect(getAssetUrlsSpy).toHaveBeenCalledWith(asset, undefined);
  });

  it('passes the shared link when resolving the asset urls', () => {
    const asset = assetFactory.build({ originalPath: 'image.gif', originalMimeType: 'image/gif' });
    const sharedLink = sharedLinkFactory.build({ allowDownload: true, showMetadata: true, assets: [asset] });
    render(PhotoViewer, { cursor: { current: asset }, sharedLink });

    expect(getAssetUrlsSpy).toHaveBeenCalledWith(asset, sharedLink);
  });

  it('resolves the asset urls again when the asset changes', async () => {
    const first = assetFactory.build({ originalPath: 'image.jpg', originalMimeType: 'image/jpeg' });
    const second = assetFactory.build({ originalPath: 'image.jpg', originalMimeType: 'image/jpeg' });
    const { rerender } = render(PhotoViewer, { cursor: { current: first } });

    await rerender({ cursor: { current: second } });

    expect(getAssetUrlsSpy).toHaveBeenCalledWith(second, undefined);
  });
});
